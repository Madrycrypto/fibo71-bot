//+------------------------------------------------------------------+
//|                                          SMC_Buffer_Test.mq5      |
//|                                    Test SMC Indicator Buffers     |
//+------------------------------------------------------------------+
#property copyright "Buffer Test"
#property version   "1.00"
#property strict

// Run this script to discover SMC indicator buffer structure

input string   g_symbol = "";          // Symbol (empty = chart symbol)

string g_symbol = "";
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;
input string   SMC_Name = "Smart Money Concepts";
input int      TestBuffers = 20;     // Number of buffers to test
input int      LookbackCandles = 500; // How many candles to check

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
    // Auto-detect symbol from chart if not specified
    g_symbol = (TradeSymbol == "") ? _Symbol : TradeSymbol;

    Print("══════════════════════════════════════════════════");
    Print("🔍 SMC Buffer Test - Extended");
    Print("Symbol: ", g_symbol);
    Print("══════════════════════════════════════════════════");

    int handle = iCustom(g_symbol, Timeframe, SMC_Name);
    if(handle == INVALID_HANDLE)
    {
        Print("❌ Cannot load indicator: ", SMC_Name);
        Print("Make sure indicator is in: MQL5/Indicators/");
        return;
    }

    Print("✅ Indicator loaded: ", SMC_Name);
    Print("Testing ", TestBuffers, " buffers over ", LookbackCandles, " candles...\n");

    // Wait for indicator to calculate
    Sleep(1000);

    // Test each buffer
    for(int buf = 0; buf < TestBuffers; buf++)
    {
        double buffer[];
        ArraySetAsSeries(buffer, true);

        if(CopyBuffer(handle, buf, 0, LookbackCandles, buffer) < 0)
        {
            Print("Buffer ", buf, ": ❌ Cannot read (error: ", GetLastError(), ")");
            continue;
        }

        // Count non-empty values and find first one
        int count = 0;
        double firstValue = 0;
        int firstIndex = -1;

        for(int i = 0; i < LookbackCandles; i++)
        {
            if(buffer[i] != 0 && buffer[i] != EMPTY_VALUE)
            {
                count++;
                if(firstIndex < 0)
                {
                    firstValue = buffer[i];
                    firstIndex = i;
                }
            }
        }

        if(count > 0)
            Print("Buffer ", buf, ": ✅ ", count, " values | First at candle[", firstIndex, "] = ", firstValue);
        else
            Print("Buffer ", buf, ": ⚪ Empty");
    }

    // Also check chart objects
    Print("\n══════════════════════════════════════════════════");
    Print("📋 Checking Chart Objects...");

    int total = ObjectsTotal(0, 0, -1);
    int smcObjects = 0;
    for(int i = 0; i < total && smcObjects < 10; i++)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "BOS") >= 0 ||
           StringFind(name, "CHOCH") >= 0 ||
           StringFind(name, "FVG") >= 0 ||
           StringFind(name, "OB") >= 0 ||
           StringFind(name, "SMC") >= 0)
        {
            Print("Found object: ", name, " | Type: ", ObjectGetInteger(0, name, OBJPROP_TYPE));
            smcObjects++;
        }
    }

    if(smcObjects == 0)
        Print("No SMC-related objects found on chart");

    Print("\n══════════════════════════════════════════════════");

    IndicatorRelease(handle);
}
//+------------------------------------------------------------------+
