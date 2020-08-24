#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
    rates_subscriptions.py
    
    An example using the Darwinex ZeroMQ Connector for Python 3 and MetaTrader 4  PULL REQUEST
    for v2.0.1 in which a Client modify instrument list configured in the EA to get rate prices 
    from EURUSD at M1 and GDAXI at M5. 
    
    After receiving 5 rates from EURUSD_M1 it cancels its feed 
    and waits 3 rates from GDAXI. At this point it cancels all rate feeds. Then it prints 
    _zmq._Market_Data_DB dictionary and finishes. 

    
    -------------------
    Rates feed:
    -------------------
    Through commmand TRACK_RATES, this client can select multiple INSTRUMENTS (symbol, timeframe).
    For example, to receive rates from instruments EURUSD(M1) and GDAXI(H1), this client
    will send this command to the Server, through its PUSH channel:

    "TRACK_RATES;EURUSD;1;GDAXI;60"

    Server will answer through the PULL channel with a json response like this:

    {'_action':'TRACK_RATES', '_data': {'instrument_count':2}}

    or if errors, then: 

    {'_action':'TRACK_RATES', '_data': {'_response':'NOT_AVAILABLE'}}

    Once subscribed to this feed, it will receive through the SUB channel, rates in this format:
    "EURUSD_M1 TIME;OPEN;HIGH;LOW;CLOSE;TICKVOL;SPREAD;REALVOL"
    "GDAXI_H1 TIME;OPEN;HIGH;LOW;CLOSE;TICKVOL;SPREAD;REALVOL"
        
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
from pandas import Timedelta, to_datetime
from threading import Thread, Lock
from time import sleep
import random


#############################################################################
# Class derived from DWZ_ZMQ_Strategy includes data processor for PULL,SUB data
#############################################################################

class rates_subscriptions(DWX_ZMQ_Strategy):
    
    def __init__(self, 
                 _name="PRICES_SUBSCRIPTIONS",
                 _instruments=[('EURUSD_M1', 'EURUSD', 1),('GDAXI_M5', 'GDAXI', 5)],
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
        self._instruments = _instruments
        self._delay = _delay
        self._verbose = _verbose
        self._finished = False

        # Initializes counters of number of rates received from each instrument
        self._eurusd_cnt = 0
        self._gdaxi_cnt  = 0
        
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
        print('Response from ExpertAdvisor={}'.format(data))
        
    ##########################################################################    
    def onSubData(self, data):        
        """
        Callback to process new data received through the SUB port
        """
        # split msg to get topic and message
        _topic, _msg = data.split(" ")
        print('Data on Topic={} with Message={}'.format(_topic, _msg))

        # increment counters
        if _topic == 'EURUSD_M1':
          self._eurusd_cnt += 1
        if _topic == 'GDAXI_M5':
          self._gdaxi_cnt += 1

        # check if received at least 5 prices from EURUSD to cancel its feed
        if self._eurusd_cnt >= 5:
          # updates the instrument list and request the update to the Expert Advisor
          self._instruments=[('GDAXI_M5', 'GDAXI', 5)]
          self.__subscribe_to_rate_feeds()
          # resets counters
          self._eurusd_cnt = 0

        # check if received at least 3 rates from GDAXI
        if self._gdaxi_cnt >= 3:
          # finishes (removes all subscriptions)  
          self.stop()
          #prints dictionary
          print(self._zmq._Market_Data_DB)
        
        
    ##########################################################################    
    def run(self):        
        """
        Starts price subscriptions
        """        
        self._finished = False

        # Subscribe to all symbols in self._symbols to receive bid,ask prices
        self.__subscribe_to_rate_feeds()

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
      
      try:
        # Acquire lock
        self._lock.acquire()
        self._zmq._DWX_MTX_SEND_TRACKPRICES_REQUEST_([])        
        print('Removing symbols list')
        sleep(self._delay)
        self._zmq._DWX_MTX_SEND_TRACKRATES_REQUEST_([])
        print('Removing instruments list')

      finally:
        # Release lock
        self._lock.release()
        sleep(self._delay)

      self._finished = True


    ##########################################################################
    def __subscribe_to_rate_feeds(self):
      """
      Starts the subscription to the self._instruments list setup during construction.
      1) Setup symbols in Expert Advisor through self._zmq._DWX_MTX_SUBSCRIBE_MARKETDATA_
      2) Starts price feeding through self._zmq._DWX_MTX_SEND_TRACKRATES_REQUEST_
      """
      if len(self._instruments) > 0:
        # subscribe to all instruments' rate feeds
        for _instrument in self._instruments:
          try:
            # Acquire lock
            self._lock.acquire()
            self._zmq._DWX_MTX_SUBSCRIBE_MARKETDATA_(_instrument[0])
            print('Subscribed to {} rate feed'.format(_instrument))
              
          finally:
            # Release lock
            self._lock.release()        
          sleep(self._delay)

        # configure instruments to receive price feeds
        try:
          # Acquire lock
          self._lock.acquire()
          self._zmq._DWX_MTX_SEND_TRACKRATES_REQUEST_(self._instruments)
          print('Configuring rate feed for {} instruments'.format(len(self._instruments)))
            
        finally:
          # Release lock
          self._lock.release()
          sleep(self._delay)     


""" -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
    SCRIPT SETUP
    -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
"""
if __name__ == "__main__":
  
  # creates object with a predefined configuration: intrument list including EURUSD_M1 and GDAXI_M5
  print('Loading example...')
  example = rates_subscriptions()  

  # Starts example execution
  print('unning example...')  
  example.run()

  # Waits example termination
  print('Waiting example termination...')
  while not example.isFinished():
    sleep(1)
  print('Bye!!!')
