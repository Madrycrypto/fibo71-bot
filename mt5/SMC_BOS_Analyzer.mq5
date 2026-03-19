//+------------------------------------------------------------------+
//|                                          SMC_BOS_Analyzer.mq5     |
//|                                    Detailed BOS Buffer Analysis   |
//+------------------------------------------------------------------+
#property copyright "SMC BOS Analyzer"
#property version   "1.00"
#property strict

input string   g_symbol = "";          // Symbol (empty = chart symbol)

string g_symbol = "";
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;
input string   SMC_Name = "Smart Money Concepts";
input int      Lookback = 100;  // Candles to analyze

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
    // Auto-detect symbol from chart if not specified
    g_symbol = (TradeSymbol == "") ? _Symbol : TradeSymbol;

    Print("══════════════════════════════════════════════════");
    Print("🔍 SMC BOS Buffer Analyzer");
    Print("Symbol: ", g_symbol);
    Print("══════════════════════════════════════════════════");

    int handle = iCustom(g_symbol, Timeframe, SMC_Name);
    if(handle == INVALID_HANDLE)
    {
        Print("❌ Cannot load indicator");
        return;
    }

    Sleep(500);

    // Analyze buffers 5, 6, 7 (likely BOS-related)
    double buf5[], buf6[], buf7[], buf14[], buf15[], buf16[], buf17[];
    ArraySetAsSeries(buf5, true);
    ArraySetAsSeries(buf6, true);
    ArraySetAsSeries(buf7, true);
    ArraySetAsSeries(buf14, true);
    ArraySetAsSeries(buf15, true);
    ArraySetAsSeries(buf16, true);
    ArraySetAsSeries(buf17, true);

    CopyBuffer(handle, 5, 0, Lookback, buf5);
    CopyBuffer(handle, 6, 0, Lookback, buf6);
    CopyBuffer(handle, 7, 0, Lookback, buf7);
    CopyBuffer(handle, 14, 0, Lookback, buf14);
    CopyBuffer(handle, 15, 0, Lookback, buf15);
    CopyBuffer(handle, 16, 0, Lookback, buf16);
    CopyBuffer(handle, 17, 0, Lookback, buf17);

    // Find candles where buffer has value
    Print("\n📊 Buffer 7 (55 values - likely BOS/CHoCH):");
    for(int i = 0; i < Lookback; i++)
    {
        if(buf7[i] != 0 && buf7[i] != EMPTY_VALUE)
        {
            double high = iHigh(g_symbol, Timeframe, i);
            double low = iLow(g_symbol, Timeframe, i);
            double close = iClose(g_symbol, Timeframe, i);

            // Check if value is near high (bullish BOS) or low (bearish BOS)
            string signal = "";
            if(MathAbs(buf7[i] - high) < 0.01) signal = "NEAR HIGH (Bullish?)";
            else if(MathAbs(buf7[i] - low) < 0.01) signal = "NEAR LOW (Bearish?)";
            else signal = "MIDDLE";

            Print("Candle[", i, "] Buffer7=", buf7[i], " | H=", high, " L=", low, " C=", close, " | ", signal);
        }
    }

    Print("\n📊 Buffer 5 + 6 (Swing High/Low):");
    for(int i = 0; i < 20; i++)
    {
        string s5 = (buf5[i] != 0 && buf5[i] != EMPTY_VALUE) ? DoubleToString(buf5[i], 2) : "-";
        string s6 = (buf6[i] != 0 && buf6[i] != EMPTY_VALUE) ? DoubleToString(buf6[i], 2) : "-";

        if(s5 != "-" || s6 != "-")
            Print("Candle[", i, "] Buf5=", s5, " | Buf6=", s6);
    }

    Print("\n📊 Buffer 14-17 (Last swing points):");
    Print("Buffer 14[0] = ", buf14[0], " | Buffer 15[0] = ", buf15[0]);
    Print("Buffer 16[0] = ", buf16[0], " | Buffer 17[0] = ", buf17[0]);

    IndicatorRelease(handle);

    Print("\n══════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
