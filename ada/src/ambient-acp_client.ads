with GNAT.Expect;
with Ada.Real_Time;
with Ambient.JSON;
with VSS.Strings;

package Ambient.ACP_Client is
   type Client is tagged limited private;
   procedure Start (Self : in out Client; Program : String);
   procedure Stop (Self : in out Client);
   function Prompt
     (Self              : in out Client;
      Session_Key, Text : String;
      Resume_Id         : String := "") return String;
   function Session (Self : Client; Key : String) return String;
private
   type Client is tagged limited record
      Process          : GNAT.Expect.Process_Descriptor;
      Running          : Boolean := False;
      Sequence         : Long_Long_Integer := 0;
      Sessions         : JSON.Value := JSON.Object_Value;
      Messages         : JSON.Value := JSON.Object_Value;
      Order            : JSON.Value := JSON.Array_Value;
      Idle, Foreground : Boolean := False;
      Current_Session  : VSS.Strings.Virtual_String;
      Deadline         : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
   end record;
end Ambient.ACP_Client;
