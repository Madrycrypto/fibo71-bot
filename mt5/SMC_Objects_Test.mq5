//+------------------------------------------------------------------+
//|                                          SMC_Objects_Test.mq5     |
//|                                    Scan SMC Chart Objects         |
//+------------------------------------------------------------------+
#property copyright "SMC Objects Test"
#property version   "1.00"
#property strict

// Scan all chart objects created by SMC indicator

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("══════════════════════════════════════════════════");
    Print("🔍 SMC Objects Scanner");
    Print("══════════════════════════════════════════════════");

    int total = ObjectsTotal(0, 0, -1);
    Print("Total objects on chart: ", total);

    // Count by prefix
    int smcCount = 0;
    int bosCount = 0;
    int chochCount = 0;
    int obCount = 0;
    int fvgCount = 0;

    string bosObjects = "";
    string chochObjects = "";

    for(int i = 0; i < total; i++)
    {
        string name = ObjectName(0, i, 0, -1);

        if(StringFind(name, "SMC_") >= 0)
        {
            smcCount++;

            // Get object details
            int objType = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
            double price1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
            double price2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
            datetime time1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
            datetime time2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);

            string typeStr = "";
            switch(objType)
            {
                case OBJ_HLINE: typeStr = "HLINE"; break;
                case OBJ_TREND: typeStr = "TREND"; break;
                case OBJ_RECTANGLE: typeStr = "RECT"; break;
                case OBJ_TEXT: typeStr = "TEXT"; break;
                case OBJ_LABEL: typeStr = "LABEL"; break;
                case OBJ_ARROW: typeStr = "ARROW"; break;
                default: typeStr = IntegerToString(objType);
            }

            Print("SMC Object: ", name, " | Type: ", typeStr,
                  " | Price1: ", price1, " | Price2: ", price2);

            // Check for BOS
            if(StringFind(name, "BOS") >= 0 || StringFind(name, "bos") >= 0)
            {
                bosCount++;
                bosObjects += name + "\n";
            }

            // Check for CHoCH
            if(StringFind(name, "CHoCH") >= 0 || StringFind(name, "choch") >= 0 ||
               StringFind(name, "CH") >= 0)
            {
                chochCount++;
                chochObjects += name + "\n";
            }

            // Check for OB
            if(StringFind(name, "OB") >= 0)
                obCount++;

            // Check for FVG
            if(StringFind(name, "FVG") >= 0 || StringFind(name, "fvg") >= 0 ||
               StringFind(name, "Imbalance") >= 0)
                fvgCount++;
        }
    }

    Print("\n══════════════════════════════════════════════════");
    Print("📊 SMC Object Summary:");
    Print("Total SMC objects: ", smcCount);
    Print("BOS objects: ", bosCount);
    Print("CHoCH objects: ", chochCount);
    Print("OB objects: ", obCount);
    Print("FVG objects: ", fvgCount);

    if(bosCount > 0)
    {
        Print("\n🔴 BOS Objects found:");
        Print(bosObjects);
    }

    if(chochCount > 0)
    {
        Print("\n🟡 CHoCH Objects found:");
        Print(chochObjects);
    }

    Print("\n══════════════════════════════════════════════════");
    Print("💡 If no BOS/CHoCH found - scroll chart to see them");
    Print("══════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
