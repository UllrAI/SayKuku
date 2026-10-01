// Portability fallback for minimal cloud runtimes that cannot enumerate interfaces.
// No network permissions change: use the verified local IPv4 loopback only.
const os = require('node:os');
const original = os.networkInterfaces;
os.networkInterfaces = function () {
  try { return original(); }
  catch (error) {
    if (error.code !== 'ERR_SYSTEM_ERROR') throw error;
    return {lo:[{address:'127.0.0.1',netmask:'255.0.0.0',family:'IPv4',mac:'00:00:00:00:00:00',internal:true,cidr:'127.0.0.1/8'}]};
  }
};
