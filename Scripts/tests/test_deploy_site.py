import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("deploy_site", Path(__file__).parents[1] / "deploy_site.py")
deploy_site = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deploy_site)


def response(value):
    return io.BytesIO(json.dumps(value).encode())


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        settings = {"COOLIFY_WEBHOOK": "https://c.ullrai.com/api/v1/deploy?uuid=site", "COOLIFY_TOKEN": "test-token"}
        environment = patch.dict(os.environ, settings)
        environment.start()
        self.addCleanup(environment.stop)

    def test_waits_for_the_queued_deployment_to_finish(self):
        replies = [response({"deployments": [{"deployment_uuid": "deployment-id"}]}),
                   response({"status": "queued"}), response({"status": "in_progress"}),
                   response({"status": "finished"})]
        with patch.object(deploy_site, "urlopen", side_effect=replies) as request, patch.object(deploy_site.time, "sleep"):
            deploy_site.main()
        methods = [call.args[0].get_method() for call in request.call_args_list]
        self.assertEqual(methods, ["POST", "GET", "GET", "GET"])
        self.assertTrue(all(call.args[0].get_header("User-agent") == "SayKuku-Deploy/1.0" for call in request.call_args_list))
        self.assertTrue(all(call.args[0].full_url.endswith("/deployments/deployment-id") for call in request.call_args_list[1:]))

    def test_a_failed_deployment_fails_the_workflow(self):
        replies = [response({"deployments": [{"deployment_uuid": "failed-id"}]}), response({"status": "failed"})]
        with patch.object(deploy_site, "urlopen", side_effect=replies), self.assertRaisesRegex(RuntimeError, "failed"):
            deploy_site.main()

    def test_an_accepted_request_without_a_deployment_is_not_success(self):
        with patch.object(deploy_site, "urlopen", return_value=response({"message": "skipped"})), self.assertRaisesRegex(RuntimeError, "did not queue"):
            deploy_site.main()

    def test_an_uncertain_post_is_never_retried(self):
        with patch.object(deploy_site, "urlopen", side_effect=TimeoutError("response interrupted")) as request:
            with self.assertRaises(TimeoutError):
                deploy_site.main()
        self.assertEqual(request.call_count, 1)


if __name__ == "__main__":
    unittest.main()
