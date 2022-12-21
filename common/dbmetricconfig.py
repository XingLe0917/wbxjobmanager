import os
import json
import socket
import requests
import base64

from common.wbxexception import wbxDataException
from common.singleton import Singleton

@Singleton
class DBMetricConfig:

    def __init__(self):
        self.loadConfigFile()
        self.loadSQLFile()
        self.hostname = None

    def getConfigFile(self):
        env_var = "PROD"
        env_file = "config.cfg"
        if os.path.isfile(env_file):
            env_dict = {}
            with open(env_file, "r") as info:
                for line in info.readlines():
                    k, v = line.split("=")
                    if k or v:
                        env_dict[k] = v.split("\n")[0]
            env_var = env_dict.get("ENV", None)
        else:
            raise Exception("there is no config.cfg file containing ENV=CHINA/PROD info!")
        CONFIGFILE_DIR = os.path.join(os.path.dirname(os.path.abspath(os.path.dirname(__file__))), "conf")
        if env_var == "CHINA":
            config_file = os.path.join(CONFIGFILE_DIR, "bjconfig.json")
        else:
            config_file = os.path.join(CONFIGFILE_DIR, "config.json")
        if not os.path.isfile(config_file):
            raise wbxDataException("file %s does not exist" % config_file)
        return config_file

    def getSQLFile(self):
        CONFIGFILE_DIR = os.path.join(os.path.dirname(os.path.abspath(os.path.dirname(__file__))), "conf")
        jobmanager_sql_file = os.path.join(CONFIGFILE_DIR, "wbxjobmanager_sql.json")
        if not os.path.isfile(jobmanager_sql_file):
            raise wbxDataException("file %s does not exist" % jobmanager_sql_file)
        return jobmanager_sql_file

    def getLoggerConfigFile(self):
        CONFIGFILE_DIR = os.path.join(os.path.dirname(os.path.abspath(os.path.dirname(__file__))), "conf")
        logger_config_file = os.path.join(CONFIGFILE_DIR, "logger.conf")
        if not os.path.isfile(logger_config_file):
            raise wbxDataException("%s does not exist" % logger_config_file);
        return logger_config_file

    def getOSWDir(self):
        return self.configDict["osw_dir"]

    def loadConfigFile(self):
        jobmanager_config_file= self.getConfigFile()
        f = open(jobmanager_config_file, "r")
        udict = json.load(f, encoding="UTF-8")
        f.close()
        self.configDict = udict
        # self.configDict = self.byteify(udict)

    def loadSQLFile(self):
        jobmanager_sql_file = self.getSQLFile()
        f = open(jobmanager_sql_file, "r")
        udict = json.load(f, encoding="UTF-8")
        f.close()
        self.sqlDict = self.byteify(udict)

    def getSQL(self, sql_name):
        if sql_name not in self.sqlDict:
            raise wbxDataException("Error: the sql %s does not exist in wbxjobmanager_sql.json file" % sql_name)
        return self.sqlDict[sql_name]

    def byteify(self, input, encoding='utf-8'):
        if isinstance(input, dict):
            # return {self.byteify(key): self.byteify(value) for key, value in input.iteritems()}
            newjson = {}
            for key, value in input.items():
                newjson[self.byteify(key)] = self.byteify(value)
            return newjson
        elif isinstance(input, list):
            # return [byteify(element) for element in input]
            newlist = []
            for element in input:
                newlist.append(self.byteify(element))
            return newlist
        # elif isinstance(input, Unicode):
        #     return input.encode(encoding)
        else:
            return input

    def getDepotDBConnectionurl(self):
        # return self.configDict["depotdb_username"], self.configDict["depotdb_password"], "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=10.252.8.105)(PORT=1701))(ADDRESS=(PROTOCOL=TCP)(HOST=10.252.8.106)(PORT=1701))(ADDRESS=(PROTOCOL=TCP)(HOST=10.252.8.107)(PORT=1701))(LOAD_BALANCE=yes)(FAILOVER=on)(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=auditdbha.webex.com)(FAILOVER_MODE=(TYPE=SELECT)(METHOD=BASIC)(RETRIES=3)(DELAY=5))))"

        token= requests.post(url=self.configDict["get_CI_token_api"],
                                 headers={"Content-Type":"application/x-www-form-urlencoded","Authorization": self.configDict["pccp_get_token_authorization"]})
        access_token = token.json()['access_token']
        token = 'Basic ' + base64.b64encode(("jobmanager" + ':' + access_token).encode('utf-8')).decode('utf-8')
        response = requests.post(url=self.configDict["pccp_depot_connection_api"],
                                 json={"data_type": "db", "data_value": "auditdb"},
                                 headers={"Authorization": token})
        if response.status_code != 200:
            raise wbxDataException("cannot get depot connection url from pccp")
        connecturl = base64.b64decode(response.text).decode('utf-8')
        return self.configDict["depotdb_username"], self.configDict["depotdb_password"], str(connecturl)


    def getpidfiledir(self):
        return self.configDict["pidfile_dir"]

    def getHostname(self):
        if self.hostname is None:
            self.hostname = socket.gethostname().split(".")[0]
        return self.hostname
        # return "txdbormt099"

    def setShareplexPortDict(self, portDict):
        self._spportDict = portDict

    def getShareplexPortDict(self):
        return self._spportDict

    def getShareplexPortInfo(self):
        spinfolist = []
        for splex_port, sp in self._spportDict.items():
            spinfolist.append(sp.getspinfo())
        return spinfolist

    def setEnv(self, env):
        self._env = env

    def getEnv(self):
        return self._env

    def setSiteCode(self, site_code):
        if site_code not in self.configDict["kafka_broker_prefix"]:
            raise wbxDataException("The site_code %s does not in config.json kafka_broker_prefix item" % site_code)
        self._site_code = site_code

    def getKafkaBrokerPrefix(self):
        return self.configDict["kafka_broker_prefix"][self._site_code]

    def getDCName(self):
        dcMapping = {"SJC02": "SJC02", "SJC03": "SJC02", "DFW01": "DFW01", "DFW02": "DFW02", "SYD01": "SYD01",
         "IAD02": "IAD02", "IAD03": "IAD02", "IAD01": "IAD02", "YYZ01": "YYZ01", "ORD10": "ORD10",
         "AMS10": "AMS01", "AMS01": "AMS01", "LHR01": "LHR03", "LHR02": "LHR03", "SYD10": "SYD10",
         "LHR03": "LHR03", "SIN01": "SIN01", "NRT03": "NRT03", "NRT02": "NRT03", "HKG10": "HKG10",
         "BLR01": "BLR03", "BLR03": "BLR03"}
        return dcMapping[self._site_code]







