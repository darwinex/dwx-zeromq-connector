# -*- coding: utf-8 -*-
"""
    DWX_ZMQ_Execution.py
    --
    @author: Darwinex Labs (www.darwinex.com)
    
    Copyright (c) 2019 onwards, Darwinex. All rights reserved.
    
    Licensed under the BSD 3-Clause License, you may not use this file except 
    in compliance with the License. 
    
    You may obtain a copy of the License at:    
    https://opensource.org/licenses/BSD-3-Clause
"""

from pandas import to_datetime
from time import sleep

# ENUM_DWX_SERV_ACTION
POS_OPEN=1
POS_CLOSE=3

class DWX_ZMQ_Execution():
    
    def __init__(self, _zmq):
        self._zmq = _zmq
    
    ##########################################################################
    
    def _execute_(self, 
                  _exec_dict,
                  _verbose=False, 
                  _delay=0.1,
                  _wbreak=10):
        
        _check = ''
        
        # Reset thread data output
        self._zmq._set_response_(None)
        
        # OPEN TRADE
        if _exec_dict['_action'] == POS_OPEN:
            
            _check = '_action'
            self._zmq._DWX_MTX_NEW_TRADE_(_order=_exec_dict)
            
        # CLOSE TRADE
        elif _exec_dict['_action'] == POS_CLOSE:
            
            _check = '_response_value'
            self._zmq._DWX_MTX_CLOSE_POSITION_BY_TICKET_(_exec_dict['_ticket'])
            
        if _verbose:
            print('\n[{}] {} -> MetaTrader'.format(_exec_dict['_comment'],
                                                   str(_exec_dict)))
            
        # While loop start time reference            
        _ws = to_datetime('now')
        
        # While data not received, sleep until timeout
        while self._zmq._valid_response_('zmq') == False:
            sleep(_delay)
            
            if (to_datetime('now') - _ws).total_seconds() > (_delay * _wbreak):
                break
        
        # If data received, return DataFrame
        if self._zmq._valid_response_('zmq'):
            
            if _check in self._zmq._get_response_().keys():
                return self._zmq._get_response_()
                
        # Default
        return None
    
    ##########################################################################
    