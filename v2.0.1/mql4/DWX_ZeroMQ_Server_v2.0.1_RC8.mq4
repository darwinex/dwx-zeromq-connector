//+--------------------------------------------------------------+
//|     DWX_ZeroMQ_Server_v2.0.1_RC8.mq4
//|     @author: Darwinex Labs (www.darwinex.com)
//|    
//|     Copyright (c) 2017-2019, Darwinex. All rights reserved.
//|    
//|     Licensed under the BSD 3-Clause License, you may not use this file except 
//|     in compliance with the License. 
//|    
//|     You may obtain a copy of the License at:    
//|     https://opensource.org/licenses/BSD-3-Clause
//+--------------------------------------------------------------+
#property copyright "Copyright 2017-2019, Darwinex Labs."
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

extern string t0 = "--- Trading Parameters ---";
extern int MagicNumber = 123456;
extern int MaximumOrders = 1;
extern double MaximumLotSize = 0.01;
extern int MaximumSlippage = 3;
extern bool DMA_MODE = true;

extern string t1 = "--- ZeroMQ Configuration ---";
extern bool Publish_MarketData = false;

string Publish_Symbols[7] = {
   "EURUSD","GBPUSD","USDJPY","USDCAD","AUDUSD","NZDUSD","USDCHF"
};

/*
string Publish_Symbols[28] = {
   "EURUSD","EURGBP","EURAUD","EURNZD","EURJPY","EURCHF","EURCAD",
   "GBPUSD","AUDUSD","NZDUSD","USDJPY","USDCHF","USDCAD","GBPAUD",
   "GBPNZD","GBPJPY","GBPCHF","GBPCAD","AUDJPY","CHFJPY","CADJPY",
   "AUDNZD","AUDCHF","AUDCAD","NZDJPY","NZDCHF","NZDCAD","CADCHF"
};
*/

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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---

   EventSetMillisecondTimer(MILLISECOND_TIMER);     // Set Millisecond Timer to get client socket input
   
   context.setBlocky(false);
   
   // Send responses to PULL_PORT that client is listening on.
   Print("[PUSH] Binding MT4 Server to Socket on Port " + IntegerToString(PULL_PORT) + "..");
   pushSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));
   
   pushSocket.setSendHighWaterMark(1);
   pushSocket.setLinger(0);
   
   // Receive commands from PUSH_PORT that client is sending to.
   Print("[PULL] Binding MT4 Server to Socket on Port " + IntegerToString(PUSH_PORT) + "..");   
   pullSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   
   pullSocket.setReceiveHighWaterMark(1);
   
   pullSocket.setLinger(0);
   
   if (Publish_MarketData == TRUE)
   {
      // Send new market data to PUB_PORT that client is subscribed to.
      Print("[PUB] Binding MT4 Server to Socket on Port " + IntegerToString(PUB_PORT) + "..");
      pubSocket.bind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
      pubSocket.setSendHighWaterMark(1);
      pubSocket.setLinger(0);
   }
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//---
    
   Print("[PUSH] Unbinding MT4 Server from Socket on Port " + IntegerToString(PULL_PORT) + "..");
   pushSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));
   
   Print("[PULL] Unbinding MT4 Server from Socket on Port " + IntegerToString(PUSH_PORT) + "..");
   pullSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   
   if (Publish_MarketData == TRUE)
   {
      Print("[PUB] Unbinding MT4 Server from Socket on Port " + IntegerToString(PUB_PORT) + "..");
      pubSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
   }
   
   // Shutdown ZeroMQ Context
   context.shutdown();
   context.destroy(0);
   
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   /*
      Use this OnTick() function to send market data to subscribed client.
   */
   if(!IsStopped() && Publish_MarketData == true)
   {
      for(int s = 0; s < ArraySize(Publish_Symbols); s++)
      {
         // Python clients can subscribe to a price feed by setting
         // socket options to the symbol name. For example:
         
         string _tick = GetBidAsk(Publish_Symbols[s]);
         Print("Sending " + Publish_Symbols[s] + " " + _tick + " to PUB Socket");
         ZmqMsg reply(StringFormat("%s %s", Publish_Symbols[s], _tick));
         pubSocket.send(reply, true);
      }
   }
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
//---

   /*
      Use this OnTimer() function to get and respond to commands
   */
   
   // Get client's response, but don't block.
   pullSocket.recv(request, true);
   
   if (request.size() > 0)
   {
      // Wait 
      // pullSocket.recv(request,false);
      
      // MessageHandler() should go here.   
      ZmqMsg reply = MessageHandler(request);
      
      // Send response, and block
      // pushSocket.send(reply);
      
      // Send response, but don't block
      pushSocket.send(reply, true);
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
      InterpretZmqMessage(&pushSocket, components);
      
   }
   else {
      // NO DATA RECEIVED
   }
   
   return(reply);
}

// Interpret Zmq Message and perform actions
void InterpretZmqMessage(Socket &pSocket, string &compArray[]) {

   // Print("ZMQ: Interpreting Message..");
   
   // Message Structures:
   
   // 1) Trading
   // TRADE|ACTION|TYPE|SYMBOL|PRICE|SL|TP|COMMENT|TICKET
   // e.g. TRADE|OPEN|1|EURUSD|0|50|50|R-to-MetaTrader4|12345678
   
   // The 12345678 at the end is the ticket ID, for MODIFY and CLOSE.
   
   // 2) Data Requests
   
   // 2.1) RATES|SYMBOL   -> Returns Current Bid/Ask
   
   // 2.2) DATA|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
   
   // NOTE: datetime has format: D'2015.01.01 00:00'
   
   /*
      compArray[0] = TRADE or RATES
      If RATES -> compArray[1] = Symbol
      
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
   if(compArray[0] == "DATA")
      switch_action = 8;
   
   string zmq_ret = "";
   string ret = "";
   int ticket = -1;
   bool ans = FALSE;
   
   switch(switch_action) 
   {
      case 1: // OPEN TRADE
         
         zmq_ret = "{";
         
         // Function definition:
         ticket = DWX_OpenOrder(compArray[3], StrToInteger(compArray[2]), StrToDouble(compArray[8]), 
                                 StrToDouble(compArray[4]), StrToInteger(compArray[5]), StrToInteger(compArray[6]), 
                                 compArray[7], StrToInteger(compArray[9]), zmq_ret);
                                 
         // Send TICKET back as JSON
         InformPullClient(pSocket, zmq_ret + "}");
         
         break;
         
      case 2: // MODIFY SL/TP
      
         zmq_ret = "{'_action': 'MODIFY'";
         
         // Function definition:
         ans = DWX_SetSLTP(StrToInteger(compArray[10]), StrToDouble(compArray[5]), StrToDouble(compArray[6]), 
                           StrToInteger(compArray[9]), StrToInteger(compArray[2]), StrToDouble(compArray[4]), 
                           compArray[3], 3, zmq_ret);
         
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
         
         ans = DWX_ClosePartial(StrToDouble(compArray[8]), zmq_ret, StrToInteger(compArray[10]));
            
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
            
      case 8: // DATA REQUEST
         
         zmq_ret = "{";
         
         DWX_GetData(compArray, zmq_ret);
         
         InformPullClient(pSocket, zmq_ret + "}");
         
         break;
         
      default: 
         break;
   }
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
    
   if(SymbolInfoTick(symbol,last_tick))
   {
       return(StringFormat("%f;%f", last_tick.bid, last_tick.ask));
   }
   
   // Default
   return "";
}

// Get data for request datetime range
void DWX_GetData(string& compArray[], string& zmq_ret) {
         
   // Format: DATA|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
   
   double price_array[];
   datetime time_array[];
   
   // Get prices
   int price_count = CopyClose(compArray[1], 
                  StrToInteger(compArray[2]), StrToTime(compArray[3]),
                  StrToTime(compArray[4]), price_array);
   
   // Get timestamps
   int time_count = CopyTime(compArray[1], 
                  StrToInteger(compArray[2]), StrToTime(compArray[3]),
                  StrToTime(compArray[4]), time_array);
      
   zmq_ret = zmq_ret + "'_action': 'DATA'";
               
   if (price_count > 0) {
      
      zmq_ret = zmq_ret + ", '_data': {";
      
      // Construct string of price|price|price|.. etc and send to PULL client.
      for(int i = 0; i < price_count; i++ ) {
         
         if(i == 0)
            zmq_ret = zmq_ret + "'" + TimeToString(time_array[i]) + "': " + DoubleToString(price_array[i]);
         else
            zmq_ret = zmq_ret + ", '" + TimeToString(time_array[i]) + "': " + DoubleToString(price_array[i]);
       
      }
      
      zmq_ret = zmq_ret + "}";
      
   }
   else {
      zmq_ret = zmq_ret + ", " + "'_response': 'NOT_AVAILABLE'";
   }
         
}

// Inform Client
void InformPullClient(Socket& pSocket, string message) {

   ZmqMsg pushReply(StringFormat("%s", message));
   
   pSocket.send(pushReply,true); // NON-BLOCKING
   
}

/*
 ############################################################################
 ############################################################################
 ############################################################################
*/

// OPEN NEW ORDER
int DWX_OpenOrder(string _symbol, int _type, double _lots, double _price, double _SL, double _TP, string _comment, int _magic, string &zmq_ret) {
   
   int ticket, error;
   
   zmq_ret = zmq_ret + "'_action': 'EXECUTION'";
   
   if(_lots > MaximumLotSize) {
      zmq_ret = zmq_ret + ", " + "'_response': 'LOT_SIZE_ERROR', 'response_value': 'MAX_LOT_SIZE_EXCEEDED'";
      return(-1);
   }
   
   double sl = _SL;
   double tp = _TP;
  
   // Else
   if(DMA_MODE) {
      sl = 0.0;
      tp = 0.0;
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
            if(DWX_SetSLTP(ticket, _SL, _TP, _magic, _type, _price, _symbol, retries, zmq_ret)) {
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

// SET SL/TP
bool DWX_SetSLTP(int ticket, double _SL, double _TP, int _magic, int _type, double _price, string _symbol, int retries, string &zmq_ret) {
   
   int dir_flag = -1;
   
   if (_type == 0 || _type == 2 || _type == 4)
      dir_flag = 1;
 
   double vpoint  = MarketInfo(OrderSymbol(), MODE_POINT);
   int    vdigits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
   
   if(OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(OrderOpenPrice()-_SL*dir_flag*vpoint,vdigits), NormalizeDouble(OrderOpenPrice()+_TP*dir_flag*vpoint,vdigits), 0, 0)) {
      zmq_ret = zmq_ret + ", '_sl': " + DoubleToString(_SL) + ", '_tp': " + DoubleToString(_TP);
      return(true);
   } else {
      int error = GetLastError();
      zmq_ret = zmq_ret + ", '_response': '" + IntegerToString(error) + "', '_response_value': '" + ErrorDescription(error) + "'";

      if(retries == 0) {
         RefreshRates();
         DWX_CloseAtMarket(-1, zmq_ret);
         // int lastOrderErrorCloseTime = TimeCurrent();
      }
      
      return(false);
   }
    
   return(true);
}

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

// CLOSE PARTIAL SIZE
bool DWX_ClosePartial(double size, string &zmq_ret, int ticket = 0) {

   RefreshRates();
   double priceCP;
   
   bool close_ret = False;
   
   if(OrderType() != OP_BUY && OrderType() != OP_SELL) {
     return(true);
   }

   if(OrderType() == OP_BUY) {
      priceCP = DWX_GetBid(OrderSymbol());
   } else {
      priceCP = DWX_GetAsk(OrderSymbol());
   }

   // If the function is called directly, setup init() JSON here.
   if(ticket != 0) {
      zmq_ret = zmq_ret + "'_action': 'CLOSE', '_ticket': " + IntegerToString(ticket);
      zmq_ret = zmq_ret + ", '_response': 'CLOSE_PARTIAL'";
   }
   
   int local_ticket = 0;
   
   if (ticket != 0)
      local_ticket = ticket;
   else
      local_ticket = OrderTicket();
   
   if(size < 0.01 || size > OrderLots()) {
      close_ret = OrderClose(local_ticket, OrderLots(), priceCP, MaximumSlippage);
      zmq_ret = zmq_ret + ", '_close_price': " + DoubleToString(priceCP) + ", '_close_lots': " + DoubleToString(OrderLots());
      return(close_ret);
   } else {
      close_ret = OrderClose(local_ticket, size, priceCP, MaximumSlippage);
      zmq_ret = zmq_ret + ", '_close_price': " + DoubleToString(priceCP) + ", '_close_lots': " + DoubleToString(size);
      return(close_ret);
   }   
}

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

string ErrorDescription(int error_code)
  {
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
//----
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



//+------------------------------------------------------------------+
