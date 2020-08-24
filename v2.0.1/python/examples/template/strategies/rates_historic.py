#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
    rates_historic.py
    
    An example using the Darwinex ZeroMQ Connector for Python 3 and MetaTrader 4 PULL REQUEST
    for v2.0.1 in which a Client requests rate history from EURGBP Daily from 2019.01.04 to
    to 2019.01.14.


    -------------------
    Rates history:
    -------------------
    Through commmand HIST, this client can select multiple rates from an INSTRUMENT (symbol, timeframe).
    For example, to receive rates from instruments EURUSD(M1), between two dates, it will send this 
    command to the Server, through its PUSH channel:

    "HIST;EURUSD;1;2019.01.04 00:00:00;2019.01.14 00:00:00"
      
    --
    
    @author: [raulMrello](https://www.linkedin.com/in/raul-martin-19254530/)
    
"""


#############################################################################
# DWX-ZMQ required imports 
#############################################################################


# Append path for main project folder
import sys
sys.path.append('../../..')

# Import ZMQ-Strategy from relative path
from examples.template.strategies.base.DWX_ZMQ_Strategy import DWX_ZMQ_Strategy


#############################################################################
# Other required imports
#############################################################################

import os
from pandas import Timedelta, to_datetime, Timestamp
from threading import Thread, Lock
from time import sleep
import random


#############################################################################
# Class derived from DWZ_ZMQ_Strategy includes data processor for PULL,SUB data
#############################################################################

class rates_historic(DWX_ZMQ_Strategy):
    
    def __init__(self, 
                 _name="PRICES_SUBSCRIPTIONS",
                 _delay=0.1,
                 _broker_gmt=3,
                 _verbose=False):
        
        # call DWX_ZMQ_Strategy constructor and passes itself as data processor for handling
        # received data on PULL and SUB ports 
        super().__init__(_name,
                         [],          # Empty symbol list (not needed for this example)
                         _broker_gmt,
                         [self],      # Registers itself as handler of pull data via self.onPullData()
                         [self],      # Registers itself as handler of sub data via self.onSubData()
                         _verbose)
        
        # This strategy's variables
        self._delay = _delay
        self._verbose = _verbose
        self._finished = False

        # lock for acquire/release of ZeroMQ connector
        self._lock = Lock()
        
    ##########################################################################    
    def isFinished(self):        
        """ Check if execution finished"""
        return self._finished
        
    ##########################################################################    
    def onPullData(self, data):        
        """
        Callback to process new data received through the PULL port
        """        
        # print responses to request commands
        print('Historic from ExpertAdvisor={}'.format(data))

        
    ##########################################################################    
    def onSubData(self, data):        
        """
        Callback to process new data received through the SUB port
        """
        # split msg to get topic and message
        _topic, _msg = data.split(" ")
        print('Data on Topic={} with Message={}'.format(_topic, _msg))

        
        
    ##########################################################################    
    def run(self):        
        """
        Request historic data
        """        
        self._finished = False

        # request rates
        print('Requesting Daily Rates from EURGBP')
        self._zmq._DWX_MTX_SEND_HIST_REQUEST_(_symbol='EURGBP',
                                              _timeframe=1440,
                                              _start='2020.05.04 00:00:00',
                                              _end  ='2020.05.14 00:00:00')
        sleep(1)
        print('\nHistory Data Dictionary:')
        print(self._zmq._History_DB)

        # finishes (removes all subscriptions)  
        self.stop()

    ##########################################################################    
    def stop(self):
      """
      unsubscribe from all market symbols and exits
      """
        
      # remove subscriptions and stop symbols price feeding
      try:
        # Acquire lock
        self._lock.acquire()
        self._zmq._DWX_MTX_UNSUBSCRIBE_ALL_MARKETDATA_REQUESTS_()
        print('Unsubscribing from all topics')
          
      finally:
        # Release lock
        self._lock.release()
        sleep(self._delay)
      
      self._finished = True



""" -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
    SCRIPT SETUP
    -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
"""
if __name__ == "__main__":
  
  # creates object with a predefined configuration: historic EURGBP_D1 between 4th adn 14th January 2019
  print('Loading example...')
  example = rates_historic()  

  # Starts example execution
  print('unning example...')  
  example.run()

  # Waits example termination
  print('Waiting example termination...')
  while not example.isFinished():
    sleep(1)
  print('Bye!!!')
