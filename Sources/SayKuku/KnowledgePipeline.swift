import Foundation

struct KnowledgeAnalysis: Equatable {
    var candidates: [ImportCandidate]
    var relationships: [ImportRelationshipCandidate]
}

enum KnowledgePipeline {
    static func chunks(_ text: String, limit: Int = 12_000) -> [String] {
        guard text.count > limit else { return text.isEmpty ? [] : [text] }
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 <= limit {
                current += current.isEmpty ? paragraph : "\n\n\(paragraph)"
                continue
            }
            if !current.isEmpty { result.append(current); current = "" }
            var remainder = paragraph[...]
            while remainder.count > limit {
                let end = remainder.index(remainder.startIndex, offsetBy: limit)
                result.append(String(remainder[..<end]))
                remainder = remainder[end...]
            }
            current = String(remainder)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func redactingPII(in source: String) -> (text: String, ignored: [ImportCandidate]) {
        let patterns = [
            #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?:地址|住址|Address)\s*[:：]\s*[^\n]{4,}"#
        ]
        var redacted = source
        var ignored: [ImportCandidate] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(redacted.startIndex..., in: redacted)
            let matches = regex.matches(in: redacted, range: range).reversed()
            for match in matches {
                guard let swiftRange = Range(match.range, in: redacted) else { continue }
                let value = String(redacted[swiftRange])
                ignored.append(ImportCandidate(
                    entity: KnowledgeEntity(name: "••••", detail: "Filtered sensitive data", type: .unknown, source: .importText),
                    status: .ignored,
                    evidence: value
                ))
                redacted.replaceSubrange(swiftRange, with: "[FILTERED]")
            }
        }
        return (redacted, ignored.reversed())
    }

    static func analyze(
        proposals: [ProposedEntity],
        relationships: [ProposedRelationship],
        existing: [KnowledgeEntity],
        existingRelationships: [KnowledgeRelationship] = [],
        ignored: [ImportCandidate]
    ) -> KnowledgeAnalysis {
        let uniqueProposals = proposals.reduce(into: [String: ProposedEntity]()) { result, proposal in
            let key = KnowledgeNormalizer.key(proposal.name)
            guard !key.isEmpty else { return }
            if var current = result[key] {
                current.aliases = Array(Set(current.aliases + proposal.aliases)).sorted()
                if current.detail.isEmpty { current.detail = proposal.detail }
                current.evidence += "\n" + proposal.evidence
                result[key] = current
            } else {
                result[key] = proposal
            }
        }.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var candidates: [ImportCandidate] = uniqueProposals.compactMap { proposal in
            let name = proposal.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !proposal.evidence.isEmpty else { return nil }
            let entity = KnowledgeEntity(
                name: name,
                detail: proposal.detail,
                type: proposal.type,
                aliases: proposal.aliases,
                source: .importText
            )
            if let match = existing.first(where: { exactMatch(entity, $0) }) {
                return ImportCandidate(entity: entity, status: .merge, evidence: proposal.evidence, matchedEntityID: match.id)
            }
            if let match = existing.first(where: { similarity(entity.normalizedKey, $0.normalizedKey) >= 0.82 }) {
                return ImportCandidate(entity: entity, status: .conflict, evidence: proposal.evidence, matchedEntityID: match.id)
            }
            return ImportCandidate(entity: entity, status: .new, evidence: proposal.evidence)
        }
        candidates.append(contentsOf: ignored)
        let knownEntities = existing + candidates.filter { $0.status != .ignored }.map(\.entity)
        let relationshipCandidates = relationships.reduce(into: [String: ImportRelationshipCandidate]()) { result, proposal in
            guard !proposal.evidence.isEmpty,
                  let from = findEntity(named: proposal.from, in: knownEntities),
                  let to = findEntity(named: proposal.to, in: knownEntities), from.id != to.id else { return }
            let key = "\(KnowledgeNormalizer.key(proposal.from))-\(proposal.type.rawValue)-\(KnowledgeNormalizer.key(proposal.to))"
            guard result[key] == nil else { return }
            let exists = existingRelationships.contains {
                $0.fromEntityID == from.id && $0.type == proposal.type && $0.toEntityID == to.id
            }
            result[key] = ImportRelationshipCandidate(relationship: proposal, status: exists ? .merge : .new)
        }.values.sorted { $0.relationship.from < $1.relationship.from }
        return KnowledgeAnalysis(candidates: candidates, relationships: relationshipCandidates)
    }

    static func commit(
        analysis: KnowledgeAnalysis,
        selectedIDs: Set<UUID>,
        existing: [KnowledgeEntity]
    ) -> (entities: [KnowledgeEntity], relationships: [KnowledgeRelationship]) {
        var entities = existing
        let chosen = analysis.candidates.filter { selectedIDs.contains($0.id) && $0.status != .ignored }
        for candidate in chosen {
            if let matchID = candidate.matchedEntityID,
               let index = entities.firstIndex(where: { $0.id == matchID }) {
                let mergedAliases = entities[index].aliases + candidate.entity.aliases + [candidate.entity.name]
                entities[index].aliases = mergedAliases.reduce(into: []) { result, alias in
                    guard KnowledgeNormalizer.key(alias) != entities[index].normalizedKey,
                          !result.contains(where: { KnowledgeNormalizer.key($0) == KnowledgeNormalizer.key(alias) }) else { return }
                    result.append(alias)
                }
                if entities[index].detail.isEmpty { entities[index].detail = candidate.entity.detail }
            } else {
                entities.append(candidate.entity)
            }
        }

        let importedNames = Set(chosen.flatMap { [$0.entity.name] + $0.entity.aliases }.map(KnowledgeNormalizer.key))
        let relationships = analysis.relationships.compactMap { candidate -> KnowledgeRelationship? in
            guard selectedIDs.contains(candidate.id) else { return nil }
            let proposal = candidate.relationship
            guard importedNames.contains(KnowledgeNormalizer.key(proposal.from)) || importedNames.contains(KnowledgeNormalizer.key(proposal.to)),
                  let from = findEntity(named: proposal.from, in: entities),
                  let to = findEntity(named: proposal.to, in: entities),
                  from.id != to.id, !proposal.evidence.isEmpty else { return nil }
            return KnowledgeRelationship(fromEntityID: from.id, type: proposal.type, toEntityID: to.id, evidence: proposal.evidence)
        }
        return (entities, relationships)
    }

    static func corrected(_ transcript: String, using entities: [KnowledgeEntity]) -> String {
        var result = transcript
        for entity in entities {
            for alias in entity.aliases.sorted(by: { $0.count > $1.count }) where !alias.isEmpty {
                result = result.replacingOccurrences(of: alias, with: entity.name, options: [.caseInsensitive])
            }
        }
        return result
    }

    private static func exactMatch(_ lhs: KnowledgeEntity, _ rhs: KnowledgeEntity) -> Bool {
        let lhsKeys = Set([lhs.normalizedKey] + lhs.aliases.map(KnowledgeNormalizer.key))
        let rhsKeys = Set([rhs.normalizedKey] + rhs.aliases.map(KnowledgeNormalizer.key))
        return !lhsKeys.isDisjoint(with: rhsKeys)
    }

    private static func findEntity(named name: String, in entities: [KnowledgeEntity]) -> KnowledgeEntity? {
        let key = KnowledgeNormalizer.key(name)
        return entities.first { $0.normalizedKey == key || $0.aliases.map(KnowledgeNormalizer.key).contains(key) }
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let left = Array(lhs), right = Array(rhs)
        var previous = Array(0...right.count)
        for (i, leftCharacter) in left.enumerated() {
            var current = [i + 1]
            for (j, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return 1 - Double(previous.last ?? max(left.count, right.count)) / Double(max(left.count, right.count))
    }
}
