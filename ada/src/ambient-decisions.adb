with Ada.Real_Time;
with Ada.Exceptions;
with VSS.Strings;
with Ambient.Models;
with Ambient.Support;

package body Ambient.Decisions is
   use JSON, Support;
   use type Ada.Real_Time.Time;
   function Available (Provider : String) return Boolean
   is (if Provider = "rules"
       then True
       elsif Provider = "llm" or Contains (Provider, "classic")
       then Models.Available
       elsif Provider = "jev"
       then Environment ("TYPESAFE_API_KEY") /= ""
       else
         Environment ("CLOUDFLARE_ACCOUNT_ID") /= ""
         and Environment ("CLOUDFLARE_API_TOKEN") /= "");
   function Provider_Info (Identifier : String) return Value is
   begin
      return
        Make_Object
          ([("id", To_JSON_String (Identifier)),
            ("label", To_JSON_String (Identifier)),
            ("kind",
             To_JSON_String
               (if Identifier = "rules"
                then "rules"
                elsif Identifier = "llm" or Contains (Identifier, "classic")
                then "llm"
                else "decision")),
            ("available", To_JSON_Boolean (Available (Identifier))),
            ("needs",
             To_JSON_String
               (if Identifier = "rules"
                then ""
                elsif Identifier = "llm" or Contains (Identifier, "classic")
                then "CHAT_COMPLETIONS_URL or an API key"
                elsif Identifier = "jev"
                then "TYPESAFE_API_KEY"
                else "CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN"))]);
   end Provider_Info;
   function Providers return Value
   is (Make_Array
         ([Provider_Info ("jev"),
           Provider_Info ("clef"),
           Provider_Info ("clef-flash"),
           Provider_Info ("llm"),
           Provider_Info ("rules")]));
   function Lanes return Value
   is (Make_Array
         ([Provider_Info ("clef-flash"),
           Provider_Info ("clef"),
           Provider_Info ("jev"),
           Provider_Info ("classic-each"),
           Provider_Info ("classic-batch")]));
   function Presets return Value is
      Result   : Value := Parse (Read_File ("ada/data/decision-presets.json"));
      Examples : Value := Array_Value;
      Storm    : constant Value := Get (Result, "storm");
   begin
      for J in 1 .. Natural'Min (Length (Storm), 6) loop
         Append
           (Examples,
            Make_Object
              ([("label", Get (Element (Storm, J), "id")),
                ("state", Get (Element (Storm, J), "state")),
                ("expected", Get (Element (Storm, J), "expected"))]));
      end loop;
      Put (Result, "examples", Examples);
      return Result;
   end Presets;
   procedure Validate (Questions : Value) is
      Names : constant Value := Member_Names (Questions);
   begin
      if not Is_Object (Questions) or Length (Names) not in 1 .. 64 then
         raise Constraint_Error with "provide 1..64 questions";
      end if;
      for J in 1 .. Length (Names) loop
         declare
            Name     : constant String := Get_Text (Element (Names, J));
            Question : constant Value := Get (Questions, Name);
            Kind     : constant String := Get_Text (Question, "type");
         begin
            if Name'Length not in 1 .. 41
              or else Name (Name'First) not in 'a' .. 'z' | 'A' .. 'Z'
            then
               raise Constraint_Error with "invalid question name";
            end if;
            for Letter of Name loop
               if Letter not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' then
                  raise Constraint_Error with "invalid question name";
               end if;
            end loop;
            if Kind not in "choice" | "score" | "noul" then
               raise Constraint_Error
                 with "question type must be choice, score or noul";
            elsif Kind = "choice"
              and then not Is_Object (Get (Question, "criteria"))
            then
               raise Constraint_Error with "choice needs criteria object";
            elsif Kind = "score"
              and then Length (Get (Question, "criteria")) < 2
            then
               raise Constraint_Error with "score needs at least two criteria";
            end if;
         end;
      end loop;
   end Validate;
   function Decide (Provider : String; State, Questions : Value) return Value
   is
      Started : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Raw     : Value;
      Answers : Value := Object_Value;
      Names   : constant Value := Member_Names (Questions);
   begin
      Validate (Questions);
      if Provider not in "jev" | "clef" | "clef-flash" | "llm" | "rules" then
         raise Constraint_Error with "unknown decision provider";
      elsif not Available (Provider) then
         raise Constraint_Error
           with "provider " & Provider & " is not configured";
      end if;
      if Provider = "rules" then
         declare
            Kind : constant String := Get_Text (State, "kind");
         begin
            if Get_Text (Get (Questions, "action"), "type") = "choice" then
               Put
                 (Answers,
                  "action",
                  Parse
                    ("{""type"":""choice"",""choice"":""act"",""confidence"":1,""probabilities"":{""act"":1,""ignore"":0,""ask"":0}}"));
            end if;
            for J in 1 .. Length (Names) loop
               declare
                  Name   : constant String := Get_Text (Element (Names, J));
                  Signal : constant String :=
                    (if Contains (Kind, "ci_")
                     then "ci"
                     elsif Contains (Kind, "pr_")
                     then "prs"
                     else "issues");
               begin
                  if Get_Text (Get (Questions, Name), "type") = "noul" then
                     Put
                       (Answers,
                        Name,
                        Make_Object
                          ([("type", To_JSON_String ("noul")),
                            ("noul",
                             To_JSON_Integer
                               (if Name = Signal then 1 else 0))]));
                  end if;
               end;
            end loop;
         end;
      else
         if Provider = "llm" then
            Raw :=
              Models.Structured
                ("Answer all questions about state. Return {answers:{questionName:{type:choice|score|noul,choice:option,confidence:0..1,probabilities:{option:probability},noul:probability_true}}}. For choice and score probabilities must sum to 1.",
                 Encode
                   (Make_Object
                      ([("state", State), ("questions", Questions)])),
                 Environment
                   ("GATE_MODEL", Environment ("CHAT_MODEL", "local-model")));
         else
            Raw :=
              Models.Post
                ((if Provider = "jev"
                  then "https://api.typesafe.ai/v1/systemone"
                  else
                    "https://api.cloudflare.com/client/v4/accounts/"
                    & Environment ("CLOUDFLARE_ACCOUNT_ID")
                    & "/ai/run/@cf/cloudflare/"
                    & Provider),
                 (if Provider = "jev"
                  then Environment ("TYPESAFE_API_KEY")
                  else Environment ("CLOUDFLARE_API_TOKEN")),
                 Make_Object
                   ([("model",
                      To_JSON_String
                        (if Provider = "jev"
                         then Environment ("JEV_MODEL", "jev-latest")
                         else Provider)),
                     ("state", State),
                     ("questions", Questions)]));
            if not Get (Raw, "result").Is_Empty then
               Raw := Get (Raw, "result");
            end if;
         end if;
         for J in 1 .. Length (Names) loop
            declare
               Name          : constant String :=
                 Get_Text (Element (Names, J));
               Kind          : constant String :=
                 Get_Text (Get (Questions, Name), "type");
               Answer        : constant Value :=
                 Get (Get (Raw, "answers"), Name);
               Probabilities : Value := Get (Answer, "probabilities");
               Best          : Value := To_JSON_String ("");
               Confidence    : Long_Float := 0.0;
               Options       : Value;
            begin
               if Kind = "noul" then
                  declare
                     Probability : constant Long_Float :=
                       Get_Number (Answer, "noul");
                  begin
                     if Probability not in 0.0 .. 1.0 then
                        raise Constraint_Error
                          with "decision probability is outside 0..1";
                     end if;
                     Put
                       (Answers,
                        Name,
                        Make_Object
                          ([("type", To_JSON_String (Kind)),
                            ("noul", To_JSON_Number (Probability))]));
                  end;
               else
                  if Length (Probabilities) > 0 then
                     declare
                        Converted : Value := Object_Value;
                     begin
                        for Index in 1 .. Length (Probabilities) loop
                           Put
                             (Converted,
                              Image (Long_Long_Integer (Index - 1)),
                              Element (Probabilities, Index));
                        end loop;
                        Probabilities := Converted;
                     end;
                  end if;
                  Options := Member_Names (Probabilities);
                  for Index in 1 .. Length (Options) loop
                     declare
                        Probability : constant Long_Float :=
                          Get_Number
                            (Probabilities,
                             Get_Text (Element (Options, Index)));
                     begin
                        if Probability not in 0.0 .. 1.0 then
                           raise Constraint_Error
                             with "decision probability is outside 0..1";
                        elsif Probability > Confidence then
                           Best := Element (Options, Index);
                           Confidence := Probability;
                        end if;
                     end;
                  end loop;
                  declare
                     Normalized : Value :=
                       Make_Object
                         ([("type", To_JSON_String (Kind)),
                           ("confidence",
                            To_JSON_Number
                              (Get_Number (Answer, "confidence", Confidence))),
                           ("probabilities", Probabilities)]);
                  begin
                     if Kind = "choice" then
                        Put
                          (Normalized,
                           "choice",
                           (if Is_String (Get (Answer, "choice"))
                            then Get (Answer, "choice")
                            else Best));
                     else
                        Put
                          (Normalized,
                           "score",
                           To_JSON_Number
                             (Get_Number
                                (Answer,
                                 "score",
                                 (if Get_Text (Best) = ""
                                  then 0.0
                                  else Long_Float'Value (Get_Text (Best))))));
                     end if;
                     Put (Answers, Name, Normalized);
                  end;
               end if;
            end;
         end loop;
      end if;
      return
        Make_Object
          ([("provider", To_JSON_String (Provider)),
            ("model",
             To_JSON_String
               (if Provider = "rules"
                then "event kind"
                elsif Provider = "llm"
                then Environment ("GATE_MODEL", "local-model")
                else Provider)),
            ("answers", Answers),
            ("ms",
             To_JSON_Number
               (Long_Float
                  (Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Started))
                * 1000.0))]);
   end Decide;
   function Race (Lane : String; States : Value) return String is
      Started   : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Result    : VSS.Strings.Virtual_String;
      Batch     : Value;
      Questions : constant Value :=
        Parse (Read_File ("ada/data/questions.json"));
   begin
      if Lane
         not in "jev"
              | "clef"
              | "clef-flash"
              | "classic-each"
              | "classic-batch"
        or Length (States) not in 1 .. 20
      then
         raise Constraint_Error
           with "race needs a known lane and 1..20 states";
      end if;
      if Lane = "classic-batch" then
         Batch :=
           Get
             (Models.Structured
                ("Return {verdicts:[{i:zero-based-index,action:act|ignore|ask,signal:ci|issues|prs}]}. Ignore reactions, act on work, ask for destructive requests.",
                 Encode (States),
                 Environment ("GATE_MODEL", "local-model")),
              "verdicts");
      end if;
      for J in 1 .. Length (States) loop
         declare
            Hit : Value :=
              Make_Object
                ([("i", To_JSON_Integer (Long_Long_Integer (J - 1)))]);
         begin
            begin
               if Lane = "classic-batch" then
                  for Index in 1 .. Length (Batch) loop
                     if Get_Integer (Element (Batch, Index), "i", -1)
                       = Long_Long_Integer (J - 1)
                     then
                        Put
                          (Hit,
                           "action",
                           Get (Element (Batch, Index), "action"));
                        Put
                          (Hit,
                           "signal",
                           Get (Element (Batch, Index), "signal"));
                     end if;
                  end loop;
               else
                  declare
                     Answer : constant Value :=
                       Get
                         (Decide
                            ((if Lane = "classic-each" then "llm" else Lane),
                             Element (States, J),
                             Questions),
                          "answers");
                     Best   : Long_Float := 0.0;
                  begin
                     Put
                       (Hit, "action", Get (Get (Answer, "action"), "choice"));
                     Put
                       (Hit,
                        "confidence",
                        Get (Get (Answer, "action"), "confidence"));
                     for Index in 1 .. 3 loop
                        declare
                           Signal      : constant String :=
                             (case Index is
                                when 1      => "ci",
                                when 2      => "issues",
                                when others => "prs");
                           Probability : constant Long_Float :=
                             Get_Number (Get (Answer, Signal), "noul");
                        begin
                           if Probability > Best then
                              Best := Probability;
                              Put (Hit, "signal", To_JSON_String (Signal));
                           end if;
                        end;
                     end loop;
                  end;
               end if;
            exception
               when Error : others =>
                  Put
                    (Hit,
                     "error",
                     To_JSON_String
                       (Ada.Exceptions.Exception_Message (Error)));
            end;
            Put
              (Hit,
               "t",
               To_JSON_Number
                 (Long_Float
                    (Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Started))
                  * 1000.0));
            Result.Append (To_Virtual_String (Encode (Hit) & ASCII.LF));
         end;
      end loop;
      return To_UTF_8_String (Result);
   end Race;
end Ambient.Decisions;
