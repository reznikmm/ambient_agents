with Ambient.JSON;

package Ambient.Decisions is
   function Providers return JSON.Value;
   function Presets return JSON.Value;
   function Lanes return JSON.Value;
   function Decide
     (Provider : String; State, Questions : JSON.Value) return JSON.Value;
   function Race (Lane : String; States : JSON.Value) return String;
end Ambient.Decisions;
