with Ambient.Engine;
with Ambient.JSON;
with Ambient.State;

package Ambient.Sources is
   function Verify_Signature
     (Secret, Body_Text, Header : String) return Boolean;
   function Signature (Secret, Body_Text : String) return String;
   function From_Webhook
     (Name, Delivery : String; Payload : JSON.Value) return JSON.Value;
   function Scenario
     (Name : String; Title : String := ""; Body_Text : String := "")
      return JSON.Value;
   type GitHub_Poller is tagged limited private;
   procedure Initialize (Self : in out GitHub_Poller; Path : String);
   procedure Poll (Self : in out GitHub_Poller; Agent : in out Engine.Agent);
private
   type GitHub_Poller is tagged limited record
      Database     : State.Store;
      Bootstrapped : Boolean := False;
   end record;
end Ambient.Sources;
