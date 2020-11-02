//+--------------------------------------------------------------+
//|     DWX_ZeroMQ_Server_v2.0.1_RC8.mq4
//|     @author: Darwinex Labs (www.darwinex.com)
//|
//|     Copyright (c) 2017-2020, Darwinex. All rights reserved.
//|    
//|     Licensed under the BSD 3-Clause License, you may not use this file except 
//|     in compliance with the License. 
//|    
//|     You may obtain a copy of the License at:    
//|     https://opensource.org/licenses/BSD-3-Clause
//+--------------------------------------------------------------+
#property copyright "Copyright 2017-2020, Darwinex Labs."
#property link      "https://www.darwinex.com/"
#property version   "2.0.1"
#property strict

// Required: MQL-ZMQ from https://github.com/dingmaotu/mql-zmq

#include <Zmq/Zmq.mqh>

extern string PROJECT_NAME = "DWX_ZeroMQ_MT4_Server";
extern string ZEROMQ_PROTOCOL = "tcp";
extern string HOSTNAME = "*";
extern int PUSH_PORT = 32768;
extern int PULL_PORT = 32769;
extern int PUB_PORT = 32770;
extern int MILLISECOND_TIMER = 1;
extern int MILLISECOND_TIMER_PRICES = 500;

extern string t0 = "--- Trading Parameters ---";
extern int MaximumOrders = 1;
extern double MaximumLotSize = 0.01;
extern int MaximumSlippage = 3;
extern bool DMA_MODE = true;

/** Now, MarketData and MarketRates flags can change in real time, according with
 *  registered symbols and instruments.
 */
//extern string t1 = "--- ZeroMQ Configuration ---";
bool Publish_MarketData  = false;
bool Publish_MarketRates = false;

long lastUpdateMillis = GetTickCount();
                                                                 
  

// Dynamic array initialized at OnInit(). Can be updated by TRACK_PRICES requests from client peers
string Publish_Symbols[];
string Publish_Symbols_LastTick[];

// CREATE ZeroMQ Context
Context context(PROJECT_NAME);

// CREATE ZMQ_PUSH SOCKET
Socket pushSocket(context, ZMQ_PUSH);

// CREATE ZMQ_PULL SOCKET
Socket pullSocket(context, ZMQ_PULL);

// CREATE ZMQ_PUB SOCKET
Socket pubSocket(context, ZMQ_PUB);

// VARIABLES FOR LATER
uchar _data[];
ZmqMsg request;

/**
 * Class definition for an specific instrument: the tuple (symbol,timeframe)
 */
class Instrument {
public:  
                
    //--------------------------------------------------------------
    /** Instrument constructor */
    Instrument() { _symbol = ""; _name = ""; _timeframe = PERIOD_CURRENT; _last_pub_rate =0;}    
                 
    //--------------------------------------------------------------
    /** Getters */
    string          symbol()    { return _symbol; }
    ENUM_TIMEFRAMES timeframe() { return _timeframe; }
    string          name()      { return _name; }
    datetime        getLastPublishTimestamp() { return _last_pub_rate; }
    /** Setters */
    void            setLastPublishTimestamp(datetime tmstmp) { _last_pub_rate = tmstmp; }
   
   //--------------------------------------------------------------
    /** Setup instrument with symbol and timeframe descriptions
     *  @param arg_symbol Symbol
     *  @param arg_timeframe Timeframe
     */
    void setup(string arg_symbol, ENUM_TIMEFRAMES arg_timeframe) {
        _symbol = arg_symbol;
        _timeframe = arg_timeframe;
        _name  = _symbol + "_" + GetTimeframeText(_timeframe);
        _last_pub_rate = 0;
    }
                
    //--------------------------------------------------------------
    /** Get last N MqlRates from this instrument (symbol-timeframe)
     *  @param rates Receives last 'count' rates
     *  @param count Number of requested rates
     *  @return Number of returned rates
     */
    int GetRates(MqlRates& rates[], int count) {
        // ensures that symbol is setup
        if(StringLen(_symbol) > 0) {
            return CopyRates(_symbol, _timeframe, 0, count, rates);
        }
        return 0;
    }
    
protected:
    string _name;                //!< Instrument descriptive name
    string _symbol;              //!< Symbol
    ENUM_TIMEFRAMES _timeframe;  //!< Timeframe
    datetime _last_pub_rate;     //!< Timestamp of the last published OHLC rate. Default = 0 (1 Jan 1970)
 
};

// Array of instruments whose rates will be published if Publish_MarketRates = True. It is initialized at OnInit() and
// can be updated through TRACK_RATES request from client peers.
Instrument Publish_Instruments[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

   EventSetMillisecondTimer(MILLISECOND_TIMER);     // Set Millisecond Timer to get client socket input
   
   context.setBlocky(false);
   
   // Send responses to PULL_PORT that client is listening on.   
   if(!pushSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT))) {
      Print("[PUSH] ####ERROR#### Binding MT4 Server to Socket on Port " + IntegerToString(PULL_PORT) + "..");
      return(INIT_FAILED);
   } else {
      Print("[PUSH] Binding MT4 Server to Socket on Port " + IntegerToString(PULL_PORT) + "..");
      pushSocket.setSendHighWaterMark(1);
      pushSocket.setLinger(0);
   }
   
   // Receive commands from PUSH_PORT that client is sending to.     
   if(!pullSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT))) {
      Print("[PULL] ####ERROR#### Binding MT4 Server to Socket on Port " + IntegerToString(PUSH_PORT) + "..");
      return(INIT_FAILED);
   } else {
      Print("[PULL] Binding MT4 Server to Socket on Port " + IntegerToString(PUSH_PORT) + "..");
      pullSocket.setReceiveHighWaterMark(1);   
      pullSocket.setLinger(0); 
   }
   
   // Send new market data to PUB_PORT that client is subscribed to.      
   if(!pubSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT))) {
      Print("[PUB] ####ERROR#### Binding MT4 Server to Socket on Port " + IntegerToString(PUB_PORT) + "..");
      return(INIT_FAILED);
   } else {
      Print("[PUB] Binding MT4 Server to Socket on Port " + IntegerToString(PUB_PORT) + "..");
      pubSocket.setSendHighWaterMark(1);
      pubSocket.setLinger(0);
   }
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

   Print("[PUSH] Unbinding MT4 Server from Socket on Port " + IntegerToString(PULL_PORT) + "..");
   pushSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));
   pushSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));
   
   Print("[PULL] Unbinding MT4 Server from Socket on Port " + IntegerToString(PUSH_PORT) + "..");
   pullSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   pullSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   
   if (Publish_MarketData == true || Publish_MarketRates == true) {
      Print("[PUB] Unbinding MT4 Server from Socket on Port " + IntegerToString(PUB_PORT) + "..");
      pubSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
      pubSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
   }
   
   // Shutdown ZeroMQ Context
   context.shutdown();
   context.destroy(0);
   
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
   /*
      Use this OnTick() function to send market data to subscribed client.
   */
   lastUpdateMillis = GetTickCount();
                                  
   if(CheckServerStatus() == true) {
      // Python clients can subscribe to a price feed for each tracked symbol
      if(Publish_MarketData == true) {
       
        for(int s = 0; s < ArraySize(Publish_Symbols); s++) {
          
          string _tick = GetBidAsk(Publish_Symbols[s]);
          // only update if bid or ask changed. 
          if (StringCompare(Publish_Symbols_LastTick[s], _tick) == 0) continue;
          Publish_Symbols_LastTick[s] = _tick;
          // publish: topic=symbol msg=tick_data
          ZmqMsg reply(StringFormat("%s %s", Publish_Symbols[s], _tick));
          Print("Sending PRICE [" + reply.getData() + "] to PUB Socket");
          if(!pubSocket.send(reply, true)) {
            Print("###ERROR### Sending price");
          }
        }
      }
      
      // Python clients can also subscribe to a rates feed for each tracked instrument
      if(Publish_MarketRates == true) {
        for(int s = 0; s < ArraySize(Publish_Instruments); s++) {
            MqlRates curr_rate[];
            int count = Publish_Instruments[s].GetRates(curr_rate, 1);
            // if last rate is returned and its timestamp is greater than the last published...
            if(count > 0 && curr_rate[0].time > Publish_Instruments[s].getLastPublishTimestamp()) {
                // then send a new pub message with this new rate
                string _rates = StringFormat("%u;%f;%f;%f;%f;%d;%d;%d",
                                    curr_rate[0].time,
                                    curr_rate[0].open, 
                                    curr_rate[0].high, 
                                    curr_rate[0].low, 
                                    curr_rate[0].close, 
                                    curr_rate[0].tick_volume, 
                                    curr_rate[0].spread, 
                                    curr_rate[0].real_volume);        
                ZmqMsg reply(StringFormat("%s %s", Publish_Instruments[s].name(), _rates));
                Print("Sending Rates @"+TimeToStr(curr_rate[0].time) + " [" + reply.getData() + "] to PUB Socket");
                if(!pubSocket.send(reply, true)) {
                    Print("###ERROR### Sending rate");            
                }
                // updates the timestamp
                Publish_Instruments[s].setLastPublishTimestamp(curr_rate[0].time);
                
          }
        }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer() {

   /*
      Use this OnTimer() function to get and respond to commands
   */
   
   if(CheckServerStatus() == true) {
      // Get client's response, but don't block.
      pullSocket.recv(request, true);
      
      if (request.size() > 0) {
         // Wait 
         // pullSocket.recv(request,false);
         
         // MessageHandler() should go here.   
         ZmqMsg reply = MessageHandler(request);
         
         // Send response, and block
         // pushSocket.send(reply);
         
         // Send response, but don't block
         if(!pushSocket.send(reply, true)) {
           Print("###ERROR### Sending message");
         }
      }
      
      // update prices regularly in case there was no tick within X milliseconds (for non-chart symbols). 
      if (GetTickCount() >= lastUpdateMillis + MILLISECOND_TIMER_PRICES) OnTick();
   }
}
//+------------------------------------------------------------------+

ZmqMsg MessageHandler(ZmqMsg &_request) {
   
   // Output object
   ZmqMsg reply;
   
   // Message components for later.
   string components[11];
   
   if(_request.size() > 0) {
   
      // Get data from request   
      ArrayResize(_data, _request.size());
      _request.getData(_data);
      string dataStr = CharArrayToString(_data);
      
      // Process data
      ParseZmqMessage(dataStr, components);
      
      // Interpret data
      InterpretZmqMessage(pushSocket, components);
      
   } else {
      // NO DATA RECEIVED
   }
   
   return(reply);
}

//+------------------------------------------------------------------+
// Interpret Zmq Message and perform actions
void InterpretZmqMessage(Socket &pSocket, string &compArray[]) {

   // Message Structures:
   
   // 1) Trading
   // TRADE|ACTION|TYPE|SYMBOL|PRICE|SL|TP|COMMENT|TICKET
   // e.g. TRADE|OPEN|1|EURUSD|0|50|50|R-to-MetaTrader4|12345678
   
   // The 12345678 at the end is the ticket ID, for MODIFY and CLOSE.
   
   // 2) Data Requests
   
   // 2.1) RATES|SYMBOL   -> Returns Current Bid/Ask
   
   // 2.2) DATA|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
   
   // 2.3) HIST|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
   
   // 3) Instruments configuration
   
   // 3.1) TRACK_PRICES|SYMBOL_1|SYMBOL_2|...|SYMBOL_N  -> List of symbols to receive real-time price updates (bid-ask)

   // 3.2) TRACK_RATES|INSTRUMENT_1|INSTRUMENT_2|...|INSTRUMENT_N  -> List of instruments to receive OHLC rates
           // Note: Instruments are bilt with format: SYMBOL_TIMEFRAME for example:
           //       Symbol: EURUSD, Timeframe: PERIOD_M1 ----> Instrument = "EURUSD_M1"          
           //       Symbol: GDAXI,  Timeframe: PERIOD_H4 ----> Instrument = "GDAXI_H4"
   
   // NOTE: datetime has format: D'2015.01.01 00:00'
   
   /*
      compArray[0] = TRADE, HIST, TRACK_PRICES, TRACK_RATES
      If HIST, TRACK_PRICES, TRACK_RATES -> compArray[1] = Symbol
      
      If TRADE ->
         compArray[0] = TRADE
         compArray[1] = ACTION (e.g. OPEN, MODIFY, CLOSE)
         compArray[2] = TYPE (e.g. OP_BUY, OP_SELL, etc - only used when ACTION=OPEN)
         
         // ORDER TYPES: 
         // https://docs.mql4.com/constants/tradingconstants/orderproperties
         
         // OP_BUY = 0
         // OP_SELL = 1
         // OP_BUYLIMIT = 2
         // OP_SELLLIMIT = 3
         // OP_BUYSTOP = 4
         // OP_SELLSTOP = 5
         
         compArray[3] = Symbol (e.g. EURUSD, etc.)
         compArray[4] = Open/Close Price (ignored if ACTION = MODIFY)
         compArray[5] = SL
         compArray[6] = TP
         compArray[7] = Trade Comment
         compArray[8] = Lots
         compArray[9] = Magic Number
         compArray[10] = Ticket Number (MODIFY/CLOSE)
   */
   
   int switch_action = 0;
   
   /* 02-08-2019 10:41 CEST - HEARTBEAT */
   if(compArray[0] == "HEARTBEAT")
      InformPullClient(pSocket, "{'_action': 'heartbeat', '_response': 'loud and clear!'}");
      
   /* Process Messages */
   if(compArray[0] == "TRADE" && compArray[1] == "OPEN")
      switch_action = 1;
   if(compArray[0] == "TRADE" && compArray[1] == "MODIFY")
      switch_action = 2;
   if(compArray[0] == "TRADE" && compArray[1] == "CLOSE")
      switch_action = 3;
   if(compArray[0] == "TRADE" && compArray[1] == "CLOSE_PARTIAL")
      switch_action = 4;
   if(compArray[0] == "TRADE" && compArray[1] == "CLOSE_MAGIC")
      switch_action = 5;
   if(compArray[0] == "TRADE" && compArray[1] == "CLOSE_ALL")
      switch_action = 6;
   if(compArray[0] == "TRADE" && compArray[1] == "GET_OPEN_TRADES")
      switch_action = 7;
   if(compArray[0] == "HIST")
      switch_action = 8;
   if(compArray[0] == "TRACK_PRICES")
      switch_action = 9;
   if(compArray[0] == "TRACK_RATES")
      switch_action = 10;
   
   // IMPORTANT: when adding new functions, also increase the max switch_action in CheckOpsStatus()!
   
   /* Setup processing variables */
   string zmq_ret = "";
   string ret = "";
   int ticket = -1;
   bool ans = false;
   
   /****************************
    * PERFORM SOME CHECKS HERE *
    ****************************/
   if (CheckOpsStatus(pSocket, switch_action) == true) {
   
      switch(switch_action) {
         case 1: // OPEN TRADE
            
            zmq_ret = "{";
            
            // Function definition:
            ticket = DWX_OpenOrder(compArray[3], StrToInteger(compArray[2]), StrToDouble(compArray[8]), StrToDouble(compArray[4]), 
                                   StrToInteger(compArray[5]), StrToInteger(compArray[6]), compArray[7], StrToInteger(compArray[9]), zmq_ret);
                                    
            // Send TICKET back as JSON
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;


         case 2: // MODIFY SL/TP
      
            zmq_ret = "{'_action': 'MODIFY'";
            
            // Function definition:
            ans = DWX_ModifyOrder(StrToInteger(compArray[10]), StrToDouble(compArray[4]), StrToDouble(compArray[5]), StrToDouble(compArray[6]), 3, zmq_ret);
            
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
         
         case 3: // CLOSE TRADE
      
            zmq_ret = "{";
            
            // IMPLEMENT CLOSE TRADE LOGIC HERE
            DWX_CloseOrder_Ticket(StrToInteger(compArray[10]), zmq_ret);
            
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
         
         case 4: // CLOSE PARTIAL
      
            zmq_ret = "{";
            
            ans = DWX_ClosePartial(StrToDouble(compArray[8]), zmq_ret, StrToInteger(compArray[10]), true);

            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
         
         case 5: // CLOSE MAGIC
      
            zmq_ret = "{";
            
            DWX_CloseOrder_Magic(StrToInteger(compArray[9]), zmq_ret);
               
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
            
         case 6: // CLOSE ALL ORDERS
      
            zmq_ret = "{";
            
            DWX_CloseAllOrders(zmq_ret);
               
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
            
         case 7: // GET OPEN ORDERS
      
            zmq_ret = "{";
            
            DWX_GetOpenOrders(zmq_ret);
               
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
         
         case 8: // HIST REQUEST
         
            zmq_ret = "{";
            
            DWX_GetHist(compArray, zmq_ret);
            
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
           
         case 9: // SETUP LIST OF SYMBOLS TO TRACK PRICES
            
            zmq_ret = "{";
            
            DWX_SetSymbolList(compArray, zmq_ret);
            
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
              
         case 10: // SETUP LIST OF INSTRUMENTS TO TRACK RATES
            
            zmq_ret = "{";
            
            DWX_SetInstrumentList(compArray, zmq_ret);
            
            InformPullClient(pSocket, zmq_ret + "}");
            
            break;
        
         // if a case is added, also change max switch_action in CheckOpsStatus()!
            
         default: 
            break;
      }
   }
}

// Check if operations are permitted
bool CheckOpsStatus(Socket &pSocket, int switch_action) {

   if (switch_action >= 1 && switch_action <= 10) {
   
      if (!IsTradeAllowed()) {
         InformPullClient(pSocket, "{'_response': 'TRADING_IS_NOT_ALLOWED__ABORTED_COMMAND'}");
         return(false);
      }
      else if (!IsExpertEnabled()) {
         InformPullClient(pSocket, "{'_response': 'EA_IS_DISABLED__ABORTED_COMMAND'}");
         return(false);
      }
      else if (IsTradeContextBusy()) {
         InformPullClient(pSocket, "{'_response': 'TRADE_CONTEXT_BUSY__ABORTED_COMMAND'}");
         return(false);
      }
      else if (!IsDllsAllowed()) {
         InformPullClient(pSocket, "{'_response': 'DLLS_DISABLED__ABORTED_COMMAND'}");
         return(false);
      }
      else if (!IsLibrariesAllowed()) {
         InformPullClient(pSocket, "{'_response': 'LIBS_DISABLED__ABORTED_COMMAND'}"); 
         return(false);
      }
      else if (!IsConnected()) {
         InformPullClient(pSocket, "{'_response': 'NO_BROKER_CONNECTION__ABORTED_COMMAND'}");
         return(false);
      }
   }
   
   return(true);
}

// Parse Zmq Message
void ParseZmqMessage(string& message, string& retArray[]) {
   
   //Print("Parsing: " + message);
   
   string sep = ";";
   ushort u_sep = StringGetCharacter(sep,0);
   
   int splits = StringSplit(message, u_sep, retArray);
   
   /*
   for(int i = 0; i < splits; i++) {
      Print(IntegerToString(i) + ") " + retArray[i]);
   }
   */
}

//+------------------------------------------------------------------+
// Generate string for Bid/Ask by symbol
string GetBidAsk(string symbol) {
   
   MqlTick last_tick;
    
   if(SymbolInfoTick(symbol,last_tick)) {
       return(StringFormat("%f;%f", last_tick.bid, last_tick.ask));
   }
   
   // Default
   return "";
}

//+------------------------------------------------------------------+
// Get historic for request datetime range
void DWX_GetHist(string& compArray[], string& zmq_ret) {
         
   // Format: HIST|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
   
   string _symbol = compArray[1];
   ENUM_TIMEFRAMES _timeframe = (ENUM_TIMEFRAMES)StrToInteger(compArray[2]);
   
   MqlRates rates_array[];
      
   // Get prices
   int rates_count = 0;
   
   // Handling ERR_HISTORY_WILL_UPDATED (4066) and ERR_NO_HISTORY_DATA (4073) errors. 
   // For non-chart symbols and time frames MT4 often needs a few requests until the data is available. 
   // But even after 10 requests it can happen that it is not available. So it is best to have the charts open. 
   for (int i=0; i<10; i++) {
      rates_count = CopyRates(_symbol, 
                              _timeframe, StrToTime(compArray[3]),
                              StrToTime(compArray[4]), rates_array);
      int errorCode = GetLastError();
      // Print("errorCode: ", errorCode);
      if (rates_count > 0 || (errorCode != 4066 && errorCode != 4073)) break;
      Sleep(200);
   }
   
   zmq_ret = zmq_ret + "'_action': 'HIST', '_symbol': '" + _symbol+ "_" + GetTimeframeText(_timeframe) + "'";
               
   // if data then forms response as json:
   // {'_action: 'HIST', 
   //  '_data':[{'time': 'YYYY:MM:DD,HH:MM:SS', 'open':0.0, 'high':0.0, 'low':0.0, 'close':0.0, 'tick_volume:0, 'spread':0, 'real_volume':0},
   //           {...},
   //           ...  
   //          ]
   // }
   if (rates_count > 0) {
      
      zmq_ret = zmq_ret + ", '_data': [";
      
      // Construct string of rates and send to PULL client.
      for(int i = 0; i < rates_count; i++ ) {
         
         if(i == 0)
            zmq_ret = zmq_ret + "{'time':'" + TimeToString(rates_array[i].time) + "', 'open':" + DoubleToString(rates_array[i].open) + ", 'high':" + DoubleToString(rates_array[i].high) + ", 'low':" + DoubleToString(rates_array[i].low) + ", 'close':" + DoubleToString(rates_array[i].close) + ", 'tick_volume':" + IntegerToString(rates_array[i].tick_volume) + ", 'spread':" + IntegerToString(rates_array[i].spread)  + ", 'real_volume':" + IntegerToString(rates_array[i].real_volume) + "}";
         else
            zmq_ret = zmq_ret + ", {'time':'" + TimeToString(rates_array[i].time) + "', 'open':" + DoubleToString(rates_array[i].open) + ", 'high':" + DoubleToString(rates_array[i].high) + ", 'low':" + DoubleToString(rates_array[i].low) + ", 'close':" + DoubleToString(rates_array[i].close) + ", 'tick_volume':" + IntegerToString(rates_array[i].tick_volume) + ", 'spread':" + IntegerToString(rates_array[i].spread)  + ", 'real_volume':" + IntegerToString(rates_array[i].real_volume) + "}";
       
      }
      
      zmq_ret = zmq_ret + "]";
      
   }
   // if NO data then forms response as json:
   // {'_action: 'HIST', 
   //  '_response': 'NOT_AVAILABLE'
   // }
   else {
      zmq_ret = zmq_ret + ", " + "'_response': 'NOT_AVAILABLE'";
   }
}

//+------------------------------------------------------------------+
// Set list of symbols to get real-time price data
void DWX_SetSymbolList(string& compArray[], string& zmq_ret) {
    
   zmq_ret = zmq_ret + "'_action': 'TRACK_PRICES'";
   
   // Format: TRACK_PRICES|SYMBOL_1|SYMBOL_2|...|SYMBOL_N
   string result = "Tracking PRICES from";
   string errorSymbols = "";
   int _num_symbols = ArraySize(compArray) - 1;
   if(_num_symbols > 0) {
      for(int s=0; s<_num_symbols; s++) {
         if (SymbolSelect(compArray[s+1], true)) {
               ArrayResize(Publish_Symbols, s+1);
               ArrayResize(Publish_Symbols_LastTick, s+1);
               Publish_Symbols[s] = compArray[s+1];
               result += " " + Publish_Symbols[s];
            } else {
               errorSymbols += "'" + compArray[s+1] + "', ";
         }
      }
      if (StringLen(errorSymbols) > 0)
         errorSymbols = "[" + StringSubstr(errorSymbols, 0, StringLen(errorSymbols)-2) + "]";
      else
         errorSymbols = "[]";
      zmq_ret = zmq_ret + ", '_data': {'symbol_count':" + IntegerToString(_num_symbols) + ", 'error_symbols':" + errorSymbols + "}";
      Publish_MarketData = true;
   } else {
      Publish_MarketData = false;
      ArrayResize(Publish_Symbols, 1);
      ArrayResize(Publish_Symbols_LastTick, 1);
      zmq_ret = zmq_ret + ", '_data': {'symbol_count': 0}";
      result += " NONE";
   }
   Print(result);
}


//+------------------------------------------------------------------+
// Set list of instruments to get OHLC rates
void DWX_SetInstrumentList(string& compArray[], string& zmq_ret) {
   
   zmq_ret = zmq_ret + "'_action': 'TRACK_RATES'";
   
   printArray(compArray);
   
   // Format: TRACK_RATES|SYMBOL_1|TIMEFRAME_1|SYMBOL_2|TIMEFRAME_2|...|SYMBOL_N|TIMEFRAME_N
   string result = "Tracking RATES from";
   string errorSymbols = "";
   int _num_instruments = (ArraySize(compArray) - 1)/2;
   if(_num_instruments > 0) {
      for(int s=0; s<_num_instruments; s++) {
         if (SymbolSelect(compArray[(2*s)+1], true)) {
            ArrayResize(Publish_Instruments, s+1);
            Publish_Instruments[s].setup(compArray[(2*s)+1], (ENUM_TIMEFRAMES)StrToInteger(compArray[(2*s)+2]));
            result += " " + Publish_Instruments[s].name();
         } else {
            errorSymbols += "'" + compArray[(2*s)+1] + "', ";
         }
      }
      if (StringLen(errorSymbols) > 0)
         errorSymbols = "[" + StringSubstr(errorSymbols, 0, StringLen(errorSymbols)-2) + "]";
      else
         errorSymbols = "[]";
      zmq_ret = zmq_ret + ", '_data': {'instrument_count':" + IntegerToString(_num_instruments) + ", 'error_symbols':" + errorSymbols + "}";
      Publish_MarketRates = true;
   } else {
      Publish_MarketRates = false;
      ArrayResize(Publish_Instruments, 1);
      zmq_ret = zmq_ret + ", '_data': {'instrument_count': 0}";
      result += " NONE";
   }
   Print(result);
}


//+------------------------------------------------------------------+
// Get Timeframe from text
string GetTimeframeText(ENUM_TIMEFRAMES tf) {
    // Standard timeframes
    switch(tf) {
        case PERIOD_M1:    return "M1";
        case PERIOD_M5:    return "M5";
        case PERIOD_M15:   return "M15";
        case PERIOD_M30:   return "M30";
        case PERIOD_H1:    return "H1";
        case PERIOD_H4:    return "H4";
        case PERIOD_D1:    return "D1";
        case PERIOD_W1:    return "W1";
        case PERIOD_MN1:   return "MN1";
        default:           return "UNKNOWN";
    }
}

// Inform Client
void InformPullClient(Socket& pSocket, string message) {

   ZmqMsg pushReply(message);
   
   pSocket.send(pushReply,true); // NON-BLOCKING
   
}

//+------------------------------------------------------------------+

// OPEN NEW ORDER
int DWX_OpenOrder(string _symbol, int _type, double _lots, double _price, double _SL, double _TP, string _comment, int _magic, string &zmq_ret) {
   
   int ticket, error;
   
   zmq_ret = zmq_ret + "'_action': 'EXECUTION'";
   
   if(_lots > MaximumLotSize) {
      zmq_ret = zmq_ret + ", " + "'_response': 'LOT_SIZE_ERROR', 'response_value': 'MAX_LOT_SIZE_EXCEEDED'";
      return(-1);
   }
   
   if(OrdersTotal() >= MaximumOrders) {
      zmq_ret = zmq_ret + ", " + "'_response': 'NUM_ORDERS_ERROR', 'response_value': 'MAX_NUMBER_OF_ORDERS_EXCEEDED'";
      return(-1);
   }
   
   if (_type == OP_BUY) 
      _price = MarketInfo(_symbol, MODE_ASK);
   else if (_type == OP_SELL) 
      _price = MarketInfo(_symbol, MODE_BID);

   
   double sl = 0.0;
   double tp = 0.0;
  
   if(!DMA_MODE) {
      int dir_flag = -1;
      
      if (_type == OP_BUY || _type == OP_BUYLIMIT || _type == OP_BUYSTOP)
         dir_flag = 1;
      
      double vpoint  = MarketInfo(_symbol, MODE_POINT);
      int    vdigits = (int)MarketInfo(_symbol, MODE_DIGITS);
      sl = NormalizeDouble(_price-_SL*dir_flag*vpoint, vdigits);
      tp = NormalizeDouble(_price+_TP*dir_flag*vpoint, vdigits);
   }
   
   if(_symbol == "NULL") {
      ticket = OrderSend(Symbol(), _type, _lots, _price, MaximumSlippage, sl, tp, _comment, _magic);
   } else {
      ticket = OrderSend(_symbol, _type, _lots, _price, MaximumSlippage, sl, tp, _comment, _magic);
   }
   if(ticket < 0) {
      // Failure
      error = GetLastError();
      zmq_ret = zmq_ret + ", " + "'_response': '" + IntegerToString(error) + "', 'response_value': '" + ErrorDescription(error) + "'";
      return(-1*error);
   }

   int tmpRet = OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES);
   
   zmq_ret = zmq_ret + ", " + "'_magic': " + IntegerToString(_magic) + ", '_ticket': " + IntegerToString(OrderTicket()) + ", '_open_time': '" + TimeToStr(OrderOpenTime(),TIME_DATE|TIME_SECONDS) + "', '_open_price': " + DoubleToString(OrderOpenPrice());

   if(DMA_MODE) {
   
      int retries = 3;
      while(true) {
         retries--;
         if(retries < 0) return(0);
         
         if((_SL == 0 && _TP == 0) || (OrderStopLoss() == _SL && OrderTakeProfit() == _TP)) {
            return(ticket);
         }

         if(DWX_IsTradeAllowed(30, zmq_ret) == 1) {
            if(DWX_ModifyOrder(ticket, _price, _SL, _TP, retries, zmq_ret)) {
               return(ticket);
            }
            if(retries == 0) {
               zmq_ret = zmq_ret + ", '_response': 'ERROR_SETTING_SL_TP'";
               return(-11111);
            }
         }

         Sleep(MILLISECOND_TIMER);
      }

      zmq_ret = zmq_ret + ", '_response': 'ERROR_SETTING_SL_TP'";
      zmq_ret = zmq_ret + "}";
      return(-1);
   }

    // Send zmq_ret to Python Client
    zmq_ret = zmq_ret + "}";
    
   return(ticket);
}

//+------------------------------------------------------------------+
// SET SL/TP
bool DWX_ModifyOrder(int ticket, double _price, double _SL, double _TP, int retries, string &zmq_ret) {
   
   if (OrderSelect(ticket, SELECT_BY_TICKET) == true) {
      
      if (OrderType() == OP_BUY || OrderType() == OP_SELL || _price == 0.0) 
         _price = OrderOpenPrice();
      
      int dir_flag = -1;
      
      if (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP)
         dir_flag = 1;
    
      double vpoint  = MarketInfo(OrderSymbol(), MODE_POINT);
      int    vdigits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
      double mSL = NormalizeDouble(_price-_SL*dir_flag*vpoint, vdigits);
      double mTP = NormalizeDouble(_price+_TP*dir_flag*vpoint, vdigits);
      
      if(OrderModify(ticket, _price, mSL, mTP, 0, 0)) {
         zmq_ret = zmq_ret + ", '_sl': " + DoubleToString(mSL) + ", '_tp': " + DoubleToString(mTP);
         return(true);
      } else {
         int error = GetLastError();
         zmq_ret = zmq_ret + ", '_response': '" + IntegerToString(error) + "', '_response_value': '" + ErrorDescription(error) + "', '_sl_attempted': " + DoubleToString(mSL, vdigits) + ", '_tp_attempted': " + DoubleToString(mTP, vdigits);
   
         if(retries == 0) {
            RefreshRates();
            DWX_CloseAtMarket(-1, zmq_ret);
         }
         
         return(false);
      }
   } else {
      zmq_ret = zmq_ret + ", '_response': 'NOT_FOUND'";
   }
   
   return(false);
}

//+------------------------------------------------------------------+
// CLOSE AT MARKET
bool DWX_CloseAtMarket(double size, string &zmq_ret) {

   int error;

   int retries = 3;
   while(true) {
      retries--;
      if(retries < 0) return(false);

      if(DWX_IsTradeAllowed(30, zmq_ret) == 1) {
         if(DWX_ClosePartial(size, zmq_ret)) {
            // trade successfuly closed
            return(true);
         } else {
            error = GetLastError();
            zmq_ret = zmq_ret + ", '_response': '" + IntegerToString(error) + "', '_response_value': '" + ErrorDescription(error) + "'";
         }
      }

   }
   return(false);
}

//+------------------------------------------------------------------+
// CLOSE PARTIAL SIZE
bool DWX_ClosePartial(double size, string &zmq_ret, int ticket=0, bool externCall=false) {

   if(OrderType() != OP_BUY && OrderType() != OP_SELL) {
      return(true);
   }

   int error;
   bool close_ret = False;
   
   // If the function is called directly, setup init() JSON here and get OrderSelect.
   if(ticket != 0 || externCall) {
      zmq_ret = zmq_ret + "'_action': 'CLOSE', '_ticket': " + IntegerToString(ticket);
      
      if (OrderSelect(ticket, SELECT_BY_TICKET)) {
         zmq_ret = zmq_ret + ", '_response': 'CLOSE_PARTIAL'";
      } else {
         zmq_ret = zmq_ret + ", '_response': 'CLOSE_PARTIAL_FAILED'";
         return(false);
      }
   }
   
   RefreshRates();
   double priceCP = OrderClosePrice();
   
   if(size < 0.01 || size > OrderLots()) {
      size = OrderLots();
   }
   close_ret = OrderClose(OrderTicket(), size, priceCP, MaximumSlippage);
   
   if (close_ret == true) {
      zmq_ret = zmq_ret + ", '_close_price': " + DoubleToString(priceCP) + ", '_close_lots': " + DoubleToString(size);
   } else {
      error = GetLastError();
      zmq_ret = zmq_ret + ", '_response': '" + IntegerToString(error) + "', '_response_value': '" + ErrorDescription(error) + "'";
   }
      
   return(close_ret);
}

//+------------------------------------------------------------------+
// CLOSE ORDER (by Magic Number)
void DWX_CloseOrder_Magic(int _magic, string &zmq_ret) {

   bool found = false;

   zmq_ret = zmq_ret + "'_action': 'CLOSE_ALL_MAGIC'";
   zmq_ret = zmq_ret + ", '_magic': " + IntegerToString(_magic);
   
   zmq_ret = zmq_ret + ", '_responses': {";
   
   for(int i=OrdersTotal()-1; i >= 0; i--) {
      if (OrderSelect(i,SELECT_BY_POS)==true && OrderMagicNumber() == _magic) {
         found = true;
         
         zmq_ret = zmq_ret + IntegerToString(OrderTicket()) + ": {'_symbol':'" + OrderSymbol() + "'";
         
         if(OrderType() == OP_BUY || OrderType() == OP_SELL) {
            DWX_CloseAtMarket(-1, zmq_ret);
            zmq_ret = zmq_ret + ", '_response': 'CLOSE_MARKET'";
            
            if (i != 0)
               zmq_ret = zmq_ret + "}, ";
            else
               zmq_ret = zmq_ret + "}";
               
         } else {
            zmq_ret = zmq_ret + ", '_response': 'CLOSE_PENDING'";
            
            if (i != 0)
               zmq_ret = zmq_ret + "}, ";
            else
               zmq_ret = zmq_ret + "}";
               
            int tmpRet = OrderDelete(OrderTicket());
         }
      }
   }

   zmq_ret = zmq_ret + "}";
   
   if(found == false) {
      zmq_ret = zmq_ret + ", '_response': 'NOT_FOUND'";
   }
   else {
      zmq_ret = zmq_ret + ", '_response_value': 'SUCCESS'";
   }
}

//+------------------------------------------------------------------+
// CLOSE ORDER (by Ticket)
void DWX_CloseOrder_Ticket(int _ticket, string &zmq_ret) {

   bool found = false;

   zmq_ret = zmq_ret + "'_action': 'CLOSE', '_ticket': " + IntegerToString(_ticket);

   for(int i=0; i<OrdersTotal(); i++) {
      if (OrderSelect(i,SELECT_BY_POS)==true && OrderTicket() == _ticket) {
         found = true;

         if(OrderType() == OP_BUY || OrderType() == OP_SELL) {
            DWX_CloseAtMarket(-1, zmq_ret);
            zmq_ret = zmq_ret + ", '_response': 'CLOSE_MARKET'";
         } else {
            zmq_ret = zmq_ret + ", '_response': 'CLOSE_PENDING'";
            int tmpRet = OrderDelete(OrderTicket());
         }
      }
   }

   if(found == false) {
      zmq_ret = zmq_ret + ", '_response': 'NOT_FOUND'";
   }
   else {
      zmq_ret = zmq_ret + ", '_response_value': 'SUCCESS'";
   }
}

//+------------------------------------------------------------------+
// CLOSE ALL ORDERS
void DWX_CloseAllOrders(string &zmq_ret) {

   bool found = false;

   zmq_ret = zmq_ret + "'_action': 'CLOSE_ALL'";
   
   zmq_ret = zmq_ret + ", '_responses': {";
   
   for(int i=OrdersTotal()-1; i >= 0; i--) {
      if (OrderSelect(i,SELECT_BY_POS)==true) {
      
         found = true;
         
         zmq_ret = zmq_ret + IntegerToString(OrderTicket()) + ": {'_symbol':'" + OrderSymbol() + "', '_magic': " + IntegerToString(OrderMagicNumber());
         
         if(OrderType() == OP_BUY || OrderType() == OP_SELL) {
            DWX_CloseAtMarket(-1, zmq_ret);
            zmq_ret = zmq_ret + ", '_response': 'CLOSE_MARKET'";
            
            if (i != 0)
               zmq_ret = zmq_ret + "}, ";
            else
               zmq_ret = zmq_ret + "}";
               
         } else {
            zmq_ret = zmq_ret + ", '_response': 'CLOSE_PENDING'";
            
            if (i != 0)
               zmq_ret = zmq_ret + "}, ";
            else
               zmq_ret = zmq_ret + "}";
               
            int tmpRet = OrderDelete(OrderTicket());
         }
      }
   }

   zmq_ret = zmq_ret + "}";
   
   if(found == false) {
      zmq_ret = zmq_ret + ", '_response': 'NOT_FOUND'";
   }
   else {
      zmq_ret = zmq_ret + ", '_response_value': 'SUCCESS'";
   }
}

//+------------------------------------------------------------------+
// GET OPEN ORDERS
void DWX_GetOpenOrders(string &zmq_ret) {

   bool found = false;

   zmq_ret = zmq_ret + "'_action': 'OPEN_TRADES'";
   zmq_ret = zmq_ret + ", '_trades': {";
   
   for(int i=OrdersTotal()-1; i>=0; i--) {
      found = true;
      
      if (OrderSelect(i,SELECT_BY_POS)==true) {
      
         zmq_ret = zmq_ret + IntegerToString(OrderTicket()) + ": {";
         
         zmq_ret = zmq_ret + "'_magic': " + IntegerToString(OrderMagicNumber()) + ", '_symbol': '" + OrderSymbol() + "', '_lots': " + DoubleToString(OrderLots()) + ", '_type': " + IntegerToString(OrderType()) + ", '_open_price': " + DoubleToString(OrderOpenPrice()) + ", '_open_time': '" + TimeToStr(OrderOpenTime(),TIME_DATE|TIME_SECONDS) + "', '_SL': " + DoubleToString(OrderStopLoss()) + ", '_TP': " + DoubleToString(OrderTakeProfit()) + ", '_pnl': " + DoubleToString(OrderProfit()) + ", '_comment': '" + OrderComment() + "'";
         
         if (i != 0)
            zmq_ret = zmq_ret + "}, ";
         else
            zmq_ret = zmq_ret + "}";
      }
   }
   zmq_ret = zmq_ret + "}";

}

//+------------------------------------------------------------------+
// counts the number of orders with a given magic number. currently not used. 
int DWX_numOpenOrdersWithMagic(int _magic) {
   int n = 0;
   for(int i=OrdersTotal()-1; i >= 0; i--) {
      if (OrderSelect(i,SELECT_BY_POS)==true && OrderMagicNumber() == _magic) {
         n++;
      }
   }
   return n;
}

//+------------------------------------------------------------------+
// CHECK IF TRADE IS ALLOWED
int DWX_IsTradeAllowed(int MaxWaiting_sec, string &zmq_ret) {
    
    if(!IsTradeAllowed()) {
    
        int StartWaitingTime = (int)GetTickCount();
        zmq_ret = zmq_ret + ", " + "'_response': 'TRADE_CONTEXT_BUSY'";
        
        while(true) {
            
            if(IsStopped()) {
                zmq_ret = zmq_ret + ", " + "'_response_value': 'EA_STOPPED_BY_USER'";
                return(-1);
            }
            
            int diff = (int)(GetTickCount() - StartWaitingTime);
            if(diff > MaxWaiting_sec * 1000) {
                zmq_ret = zmq_ret + ", '_response': 'WAIT_LIMIT_EXCEEDED', '_response_value': " + IntegerToString(MaxWaiting_sec);
                return(-2);
            }
            // if the trade context has become free,
            if(IsTradeAllowed()) {
                zmq_ret = zmq_ret + ", '_response': 'TRADE_CONTEXT_NOW_FREE'";
                RefreshRates();
                return(1);
            }
            
          }
    } else {
        return(1);
    }
    return(1);
}

bool CheckServerStatus() {

   // Is _StopFlag == True, inform the client application
   if (IsStopped()) {
      InformPullClient(pullSocket, "{'_response': 'EA_IS_STOPPED'}");
      return(false);
   }
   
   // Default
   return(true);
}

string ErrorDescription(int error_code) {
   string error_string;
//----
   switch(error_code)
     {
      //---- codes returned from trade server
      case 0:
      case 1:   error_string="no error";                                                  break;
      case 2:   error_string="common error";                                              break;
      case 3:   error_string="invalid trade parameters";                                  break;
      case 4:   error_string="trade server is busy";                                      break;
      case 5:   error_string="old version of the client terminal";                        break;
      case 6:   error_string="no connection with trade server";                           break;
      case 7:   error_string="not enough rights";                                         break;
      case 8:   error_string="too frequent requests";                                     break;
      case 9:   error_string="malfunctional trade operation (never returned error)";      break;
      case 64:  error_string="account disabled";                                          break;
      case 65:  error_string="invalid account";                                           break;
      case 128: error_string="trade timeout";                                             break;
      case 129: error_string="invalid price";                                             break;
      case 130: error_string="invalid stops";                                             break;
      case 131: error_string="invalid trade volume";                                      break;
      case 132: error_string="market is closed";                                          break;
      case 133: error_string="trade is disabled";                                         break;
      case 134: error_string="not enough money";                                          break;
      case 135: error_string="price changed";                                             break;
      case 136: error_string="off quotes";                                                break;
      case 137: error_string="broker is busy (never returned error)";                     break;
      case 138: error_string="requote";                                                   break;
      case 139: error_string="order is locked";                                           break;
      case 140: error_string="long positions only allowed";                               break;
      case 141: error_string="too many requests";                                         break;
      case 145: error_string="modification denied because order too close to market";     break;
      case 146: error_string="trade context is busy";                                     break;
      case 147: error_string="expirations are denied by broker";                          break;
      case 148: error_string="amount of open and pending orders has reached the limit";   break;
      case 149: error_string="hedging is prohibited";                                     break;
      case 150: error_string="prohibited by FIFO rules";                                  break;
      //---- mql4 errors
      case 4000: error_string="no error (never generated code)";                          break;
      case 4001: error_string="wrong function pointer";                                   break;
      case 4002: error_string="array index is out of range";                              break;
      case 4003: error_string="no memory for function call stack";                        break;
      case 4004: error_string="recursive stack overflow";                                 break;
      case 4005: error_string="not enough stack for parameter";                           break;
      case 4006: error_string="no memory for parameter string";                           break;
      case 4007: error_string="no memory for temp string";                                break;
      case 4008: error_string="not initialized string";                                   break;
      case 4009: error_string="not initialized string in array";                          break;
      case 4010: error_string="no memory for array\' string";                             break;
      case 4011: error_string="too long string";                                          break;
      case 4012: error_string="remainder from zero divide";                               break;
      case 4013: error_string="zero divide";                                              break;
      case 4014: error_string="unknown command";                                          break;
      case 4015: error_string="wrong jump (never generated error)";                       break;
      case 4016: error_string="not initialized array";                                    break;
      case 4017: error_string="dll calls are not allowed";                                break;
      case 4018: error_string="cannot load library";                                      break;
      case 4019: error_string="cannot call function";                                     break;
      case 4020: error_string="expert function calls are not allowed";                    break;
      case 4021: error_string="not enough memory for temp string returned from function"; break;
      case 4022: error_string="system is busy (never generated error)";                   break;
      case 4050: error_string="invalid function parameters count";                        break;
      case 4051: error_string="invalid function parameter value";                         break;
      case 4052: error_string="string function internal error";                           break;
      case 4053: error_string="some array error";                                         break;
      case 4054: error_string="incorrect series array using";                             break;
      case 4055: error_string="custom indicator error";                                   break;
      case 4056: error_string="arrays are incompatible";                                  break;
      case 4057: error_string="global variables processing error";                        break;
      case 4058: error_string="global variable not found";                                break;
      case 4059: error_string="function is not allowed in testing mode";                  break;
      case 4060: error_string="function is not confirmed";                                break;
      case 4061: error_string="send mail error";                                          break;
      case 4062: error_string="string parameter expected";                                break;
      case 4063: error_string="integer parameter expected";                               break;
      case 4064: error_string="double parameter expected";                                break;
      case 4065: error_string="array as parameter expected";                              break;
      case 4066: error_string="requested history data in update state";                   break;
      case 4099: error_string="end of file";                                              break;
      case 4100: error_string="some file error";                                          break;
      case 4101: error_string="wrong file name";                                          break;
      case 4102: error_string="too many opened files";                                    break;
      case 4103: error_string="cannot open file";                                         break;
      case 4104: error_string="incompatible access to a file";                            break;
      case 4105: error_string="no order selected";                                        break;
      case 4106: error_string="unknown symbol";                                           break;
      case 4107: error_string="invalid price parameter for trade function";               break;
      case 4108: error_string="invalid ticket";                                           break;
      case 4109: error_string="trade is not allowed in the expert properties";            break;
      case 4110: error_string="longs are not allowed in the expert properties";           break;
      case 4111: error_string="shorts are not allowed in the expert properties";          break;
      case 4200: error_string="object is already exist";                                  break;
      case 4201: error_string="unknown object property";                                  break;
      case 4202: error_string="object is not exist";                                      break;
      case 4203: error_string="unknown object type";                                      break;
      case 4204: error_string="no object name";                                           break;
      case 4205: error_string="object coordinates error";                                 break;
      case 4206: error_string="no specified subwindow";                                   break;
      default:   error_string="unknown error";
      }
   return(error_string);
}
  
//+------------------------------------------------------------------+

double DWX_GetAsk(string symbol) {
   if(symbol == "NULL") {
      return(Ask);
   } else {
      return(MarketInfo(symbol,MODE_ASK));
   }
}

//+------------------------------------------------------------------+

double DWX_GetBid(string symbol) {
   if(symbol == "NULL") {
      return(Bid);
   } else {
      return(MarketInfo(symbol,MODE_BID));
   }
}
//+------------------------------------------------------------------+

void printArray(string &arr[]) {
   if (ArraySize(arr) == 0) Print("{}");
   string printStr = "{";
   int i;
   for (i=0; i<ArraySize(arr); i++) {
      if (i == ArraySize(arr)-1) printStr += arr[i];
      else printStr += arr[i] + ", ";
   }
   Print(printStr + "}");
}

//+------------------------------------------------------------------+