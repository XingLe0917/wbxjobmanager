#!/bin/env python

__author__ = 'edwin'

import urllib2
import sys

url_cron = 'https://stapalpha.webex.com/API/dataservice/crontabl/addCronLog'
headers = {'Content-Type': 'application/json'}


def call_stap(data):
    try:
        request = urllib2.Request(url=url_cron, headers=headers, data=data)
        response = urllib2.urlopen(request)
        v_return = response.read()

        # print "====== call result:"
        print v_return

    except Exception, e:
        print "ERROR_WHILE_CALL_STAP_API"
        v_err = str(e)


if __name__ == '__main__':

    if len(sys.argv) < 2:
        print "NO_INPUT"
    else:
        call_stap(str(sys.argv[1]))

