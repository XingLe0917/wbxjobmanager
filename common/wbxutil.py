import datetime, time
import json
import logging
import string
import random
import calendar
# from dateutil import tz
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import smtplib
from email.header import Header
import subprocess
import os


timeformat = "%Y-%m-%d %H:%M:%S"
dateformat = "%Y-%m-%d"

logger = logging.getLogger("DBAMONITOR")

class wbxutil:

    @staticmethod
    def isNoneString(str):
        if str is None or str.strip() == '':
            return True
        else:
            return False

    @staticmethod
    def getcurrenttime(timerange = None):
        if timerange is None:
            return datetime.datetime.utcnow()
        else:
            mytime = datetime.datetime.utcnow() - datetime.timedelta(seconds=timerange)
            return mytime

    @staticmethod
    def gettimestr(timerange = None):
        if timerange is None:
            return datetime.datetime.utcnow().strftime(timeformat)
        else:
            mytime = datetime.datetime.utcnow() + datetime.timedelta(seconds=timerange)
            return mytime.strftime(timeformat)

    @staticmethod
    def getCurrentTimeAsStringForKibana():
        NEW_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
        return datetime.datetime.now().strftime(NEW_FORMAT)

    @staticmethod
    def convertStringtoDateTime(str):
        if str is None or str == '':
            return None
        return datetime.datetime.strptime(str, timeformat)

    # @staticmethod
    # def convertStringToGMTString(str):
    #     if str is None:
    #         return None
    #     from_tz = tz.gettz('America/Los_Angeles')
    #     to_tz = tz.tzutc()
    #     dt = datetime.datetime.strptime(str, timeformat)
    #     dt = dt.replace(tzinfo=from_tz)
    #     central = dt.astimezone(to_tz)
    #     return wbxutil.convertDatetimeToString(central)


    @staticmethod
    def convertDatetimeToString(dtime):
        if dtime is None:
            return ""
        return datetime.datetime.strftime(dtime, timeformat)

    @staticmethod
    def convertStringToDate(ddate):
        if ddate is None:
            return ""
        return datetime.datetime.strptime(ddate, dateformat)

    @staticmethod
    def convertTimeToDateTime(ttime):
        return  datetime.datetime(*ttime[0:6])

    @staticmethod
    def convertTimeToString(ttime):
        time.strftime(timeformat, ttime)

    @staticmethod
    def convertTimestampToString(ttimestamp):
        curdatetime = datetime.datetime.utcfromtimestamp(ttimestamp)
        return wbxutil.convertDatetimeToString(curdatetime)

    @staticmethod
    def convertStringToTimestamp(str):
        d = wbxutil.convertStringtoDateTime(str)
        return calendar.timegm(d.timetuple())

    @staticmethod
    def convertTimestampToDatetime(ttimestamp):
        curdatetime = datetime.datetime.utcfromtimestamp(ttimestamp)
        return curdatetime

    @staticmethod
    def convertDateTimeToStringForES(dt):
        NEW_FORMAT = "%Y-%m-%dT%H:%M:%S.%f"
        return dt.strftime(NEW_FORMAT)[:-3]

    def convertESStringToDatetime(str_datetime):
        NEW_FORMAT = "%Y-%m-%dT%H:%M:%S.%f"
        return datetime.datetime.strptime(str_datetime, NEW_FORMAT)

    @staticmethod
    def convertString(xstr):
        if xstr is None:
            return xstr
        elif xstr.strip() == '':
            return None
        else:
            return str(xstr)

    @staticmethod
    def convertSizeToByte(dsize, unit):
        unitpercent = {"B":0,"K":1,"M":2,"G":3,"T":4}
        return float(dsize) * pow(1024, unitpercent[unit])

    @staticmethod
    def convertORM2Dict(obj):
        fields = {}
        for field in [x for x in dir(obj) if not x.startswith('_') and x != 'metadata']:
            val = obj.__getattribute__(field)
            try:
                json.dumps(val)  # this will fail on non-encodable values, like other classes
                fields[field] = val
            except TypeError as e:
                logger.error(type(obj))
                logger.error(e)
                fields[field] = None

            fields[field] = val
        return fields

    @staticmethod
    def getShareplexSchemanamebyPort(port):
        return "splex%s" % port

    @staticmethod
    def generateNewPassword():
        chars = string.ascii_letters + string.digits
        length = random.randint(8,12)
        while True:
            pos = random.randint(2, length - 3)
            hasupper = haslower = hasdigit = False
            pwd = ''.join([random.choice(chars) if i != pos else '#' for i in range(length)])
            if pwd[0] in string.digits:
                continue

            for c in pwd:
                if c in string.ascii_uppercase:
                    hasupper = True
                elif c in string.ascii_lowercase:
                    haslower = True
                elif c in string.digits:
                    hasdigit = True

            if hasupper and haslower and hasdigit:
                return pwd

    @staticmethod
    def installdbpatch(releasenumber):
        release_name = "WBXdbpatch-%s" % releasenumber
        p = subprocess.Popen('sudo rpm -qa | grep %s' % release_name, shell=True, stdout=subprocess.PIPE)
        out, err = p.communicate()
        vres = out.decode("ascii").strip().replace("\n", "")
        if not (vres is None or "" == vres):
            subprocess.Popen("sudo rpm -e %s" % vres, shell=True, stdout=subprocess.PIPE)
        release_dir = os.path.join("/tmp", str(releasenumber))
        if os.path.isdir(release_dir):
            subprocess.Popen('sudo rm -rf %s' % release_dir, shell=True, stdout=subprocess.PIPE)
        os.system("sudo yum -y install %s" % release_name)

    @staticmethod
    def sendmail(emailtopic, emailcontent, emailformat="text"):
        try:
            sender = "dbamonitortool@cisco.com"
            mailto = ["zhiwliu@cisco.com"]
            message = MIMEText(emailcontent, _subtype=emailformat, _charset='utf-8')
            message['From'] = Header(sender)
            message['To'] = Header(",".join(mailto))
            message['Subject'] = Header(emailtopic)

            smtpObj = smtplib.SMTP(host='mda.webex.com:25')
            senderrs = smtpObj.sendmail(sender, mailto, message.as_string())
            if len(senderrs) > 0:
                logger.error("Unexpected error:{0}".format(senderrs))
            smtpObj.quit()
        except smtplib.SMTPException:
            pass


if __name__ == "__main__":
    wbxutil.sendmail("test","test")

