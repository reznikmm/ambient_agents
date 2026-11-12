with Ada.Characters.Handling;
with Ambient.Support;

package body Ambient.Types is
   use JSON, Support;
   function Name (Kind : Event_Kind) return String
   is (Ada.Characters.Handling.To_Lower (Kind'Image));
   function Name (Item : Signal) return String
   is (Ada.Characters.Handling.To_Lower (Item'Image));
   function Signal_Of (Item : Agent_Event) return Signal is
   begin
      if Item.Kind in CI_Failed | CI_Passed
        or Contains (To_UTF_8_String (Item.Subject), "ci:")
      then
         return CI;
      elsif Item.Kind in PR_Opened | PR_Comment then
         return PRs;
      else
         return Issues;
      end if;
   end Signal_Of;
   function Decode (Item : Value) return Agent_Event is
      Result : Agent_Event;
      Actor  : constant Value := Get (Item, "actor");
   begin
      if not Is_Object (Item)
        or else Get_Text (Item, "id") = ""
        or else Get_Text (Item, "subject") = ""
      then
         raise Constraint_Error with "event requires id, kind and subject";
      end if;
      Result.Id := To_Virtual_String (Get_Text (Item, "id"));
      Result.Source := To_Virtual_String (Get_Text (Item, "source"));
      Result.Kind := Event_Kind'Value (Get_Text (Item, "kind"));
      Result.Login := To_Virtual_String (Get_Text (Actor, "login"));
      Result.Bot := Get_Boolean (Actor, "bot");
      Result.Subject := To_Virtual_String (Get_Text (Item, "subject"));
      Result.Title := To_Virtual_String (Get_Text (Item, "title"));
      Result.Body_Text := To_Virtual_String (Get_Text (Item, "body"));
      Result.URL := To_Virtual_String (Get_Text (Item, "url"));
      Result.Watch := To_Virtual_String (Get_Text (Item, "watch"));
      Result.At_Time := Get_Integer (Item, "at");
      Result.Routing :=
        (if Get_Text (Item, "route") = ""
         then Signal_Of (Result)
         else Signal'Value (Get_Text (Item, "route")));
      return Result;
   end Decode;
   function Encode (Item : Agent_Event) return Value is
   begin
      return
        Make_Object
          ([("id", To_JSON_String (To_UTF_8_String (Item.Id))),
            ("source", To_JSON_String (To_UTF_8_String (Item.Source))),
            ("kind", To_JSON_String (Name (Item.Kind))),
            ("actor",
             Make_Object
               ([("login", To_JSON_String (To_UTF_8_String (Item.Login))),
                 ("bot", To_JSON_Boolean (Item.Bot))])),
            ("subject", To_JSON_String (To_UTF_8_String (Item.Subject))),
            ("title", To_JSON_String (To_UTF_8_String (Item.Title))),
            ("body", To_JSON_String (To_UTF_8_String (Item.Body_Text))),
            ("url", To_JSON_String (To_UTF_8_String (Item.URL))),
            ("watch", To_JSON_String (To_UTF_8_String (Item.Watch))),
            ("route", To_JSON_String (Name (Item.Routing))),
            ("at", To_JSON_Integer (Item.At_Time))]);
   end Encode;
   function Decode_Result (Item : Value) return Worker_Result is
      Result : Worker_Result;
      Wake   : constant Long_Long_Integer :=
        Get_Integer (Item, "wakeupInMinutes");
   begin
      if not Is_String (Get (Item, "summary"))
        or else not Is_String (Get (Item, "action"))
        or else not Is_Boolean (Get (Item, "reversible"))
        or else Get_Number (Item, "confidence", -1.0) not in 0.0 .. 1.0
        or else Wake not in 0 .. 525_600
      then
         raise Constraint_Error with "invalid worker result";
      end if;
      Result.Summary := To_Virtual_String (Get_Text (Item, "summary"));
      Result.Action := To_Virtual_String (Get_Text (Item, "action"));
      Result.Reversible := Get_Boolean (Item, "reversible");
      Result.Confidence := Get_Number (Item, "confidence");
      Result.Wakeup_Minutes := Natural (Wake);
      Result.Commented := Get_Boolean (Item, "commented");
      return Result;
   end Decode_Result;
   function Encode_Result (Item : Worker_Result) return Value is
   begin
      return
        Make_Object
          ([("sessionId",
             To_JSON_String (To_UTF_8_String (Item.Session_Identifier))),
            ("summary", To_JSON_String (To_UTF_8_String (Item.Summary))),
            ("action", To_JSON_String (To_UTF_8_String (Item.Action))),
            ("reversible", To_JSON_Boolean (Item.Reversible)),
            ("confidence", To_JSON_Number (Item.Confidence)),
            ("wakeupInMinutes",
             To_JSON_Integer (Long_Long_Integer (Item.Wakeup_Minutes))),
            ("commented", To_JSON_Boolean (Item.Commented))]);
   end Encode_Result;
   function Encode (Item : Statistics) return Value is
   begin
      return
        Make_Object
          ([("received", To_JSON_Integer (Long_Long_Integer (Item.Received))),
            ("filtered", To_JSON_Integer (Long_Long_Integer (Item.Filtered))),
            ("gateCalls",
             To_JSON_Integer (Long_Long_Integer (Item.Gate_Calls))),
            ("ignored", To_JSON_Integer (Long_Long_Integer (Item.Ignored))),
            ("merged", To_JSON_Integer (Long_Long_Integer (Item.Merged))),
            ("workerRuns",
             To_JSON_Integer (Long_Long_Integer (Item.Worker_Runs))),
            ("activeWorkers",
             To_JSON_Integer (Long_Long_Integer (Item.Active_Workers))),
            ("maxWorkers",
             To_JSON_Integer (Long_Long_Integer (Item.Max_Workers))),
            ("pingsSent",
             To_JSON_Integer (Long_Long_Integer (Item.Pings_Sent))),
            ("pingsHeld",
             To_JSON_Integer (Long_Long_Integer (Item.Pings_Held))),
            ("timersFired",
             To_JSON_Integer (Long_Long_Integer (Item.Timers_Fired))),
            ("sessions",
             To_JSON_Integer (Long_Long_Integer (Item.Sessions)))]);
   end Encode;
end Ambient.Types;
