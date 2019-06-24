# -*- coding: utf-8 -*-
"""
    DWX_ZMQ_Reporting.py
    --
    @author: Darwinex Labs (www.darwinex.com)
    
    Copyright (c) 2019 onwards, Darwinex. All rights reserved.
    
    Licensed under the BSD 3-Clause License, you may not use this file except 
    in compliance with the License. 
    
    You may obtain a copy of the License at:    
    https://opensource.org/licenses/BSD-3-Clause
"""

from pandas import DataFrame, to_datetime
from time import sleep

class DWX_ZMQ_Reporting():
    
    def __init__(self, _zmq):
        self._zmq = _zmq
        
    ##########################################################################
    
    def _get_open_trades_(self, _trader='Trader_SYMBOL', 
                          _delay=0.1, _wbreak=10):
        
        # Reset data output
        self._zmq._set_response_(None)
        
        # Get open trades from MetaTrader
        self._zmq._DWX_MTX_GET_ALL_OPEN_TRADES_()

        # While loop start time reference            
        _ws = to_datetime('now')
        
        # While data not received, sleep until timeout
        while self._zmq._valid_response_('zmq') == False:
            
            sleep(_delay)
            
            if (to_datetime('now') - _ws).total_seconds() > (_delay * _wbreak):
                break
        
        # If data received, return DataFrame
        if self._zmq._valid_response_('zmq'):
            
            _response = self._zmq._get_response_()
            
            if ('_trades' in _response.keys()
                and len(_response['_trades']) > 0):
                
                _df = DataFrame(data=_response['_trades'].values(),
                                index=_response['_trades'].keys())
                return _df[_df['_comment'] == _trader]
            
        # Default
        return DataFrame()
    
    ##########################################################################
    