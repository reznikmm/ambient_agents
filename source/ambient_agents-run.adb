--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Latin_1;
with Ada.IO_Exceptions;
with Ada.Strings.Unbounded;

with Interfaces.C_Streams;

with VSS.Command_Line;
with VSS.Strings.Conversions;
with VSS.Text_Streams.Standards;

with Ambient_Agents.Agents;
with Ambient_Agents.Clocks;
with Ambient_Agents.Sessions;
with Ambient_Agents.Signals;
with Ambient_Agents.Threads;

--  Read console commands and keep the state of the running workshop demo.

procedure Ambient_Agents.Run is
   package C_Streams renames Interfaces.C_Streams;
   use VSS.Strings;
   use VSS.Strings.Conversions;

   Agent   : Agents.Agent;
   Clock   : Clocks.Clock;
   Session : Sessions.Session;
   Thread  : Threads.Thread;

   Output : VSS.Text_Streams.Output_Text_Stream'Class :=
     VSS.Text_Streams.Standards.Standard_Output;

   Errors : VSS.Text_Streams.Output_Text_Stream'Class :=
     VSS.Text_Streams.Standards.Standard_Error;

   procedure Print
     (Line   : Virtual_String;
      Stream : in out VSS.Text_Streams.Output_Text_Stream'Class);
   --  Write a line and report any stream error as an I/O exception.

   function Read_Line (Line : out Virtual_String) return Boolean;
   --  Read one UTF-8 line. Return False at EOF with no bytes left to read.

   procedure Send (Message : Virtual_String);
   --  Send a user message and record the visible reply in the thread.

   procedure Simulate;
   --  Submit a sample CI failure through the normal signal entry point.

   procedure Show_Thread;
   --  Display the conversation in chronological order.

   procedure Print
     (Line   : Virtual_String;
      Stream : in out VSS.Text_Streams.Output_Text_Stream'Class)
   is
      Success : Boolean := True;
   begin
      Stream.Put_Line (Line, Success);

      if not Success then
         raise Ada.IO_Exceptions.Device_Error
           with
             "Writing console output: "
             & To_UTF_8_String (Stream.Error_Message);
      end if;
   end Print;

   function Read_Line (Line : out Virtual_String) return Boolean is
      package Latin_1 renames Ada.Characters.Latin_1;
      use Ada.Strings.Unbounded;

      Input : constant C_Streams.FILEs := C_Streams.stdin;
      Bytes : Unbounded_String;
      Byte  : C_Streams.int;
   begin
      --  VSS.Text_Streams.Standards exposes only output streams.
      loop
         Byte := C_Streams.fgetc (Input);
         exit when
           Byte = C_Streams.EOF or else Byte = Character'Pos (Latin_1.LF);

         Append (Bytes, Character'Val (Byte));
      end loop;

      if Byte = C_Streams.EOF then
         if C_Streams.ferror (Input) /= 0 then
            raise Ada.IO_Exceptions.Device_Error
              with "Reading standard input failed";
         end if;

         if Length (Bytes) = 0 then
            return False;
         end if;
      elsif Length (Bytes) > 0
        and then Element (Bytes, Length (Bytes)) = Latin_1.CR
      then
         Delete (Bytes, Length (Bytes), Length (Bytes));
      end if;

      Line := To_Virtual_String (Bytes);
      return True;
   end Read_Line;

   procedure Send (Message : Virtual_String) is
      Answer : Virtual_String;

      procedure Show (Part : Sessions.Chat_Part);
      --  Collect reply text and display tool activity and errors.

      procedure Show (Part : Sessions.Chat_Part) is
      begin
         case Part.Kind is
            when Sessions.Text                             =>
               Answer.Append (Part.Content);

            when Sessions.Tool_Call | Sessions.Tool_Result =>
               Print (Part.Tool_Name & ": " & Part.Payload, Output);

            when Sessions.Error                            =>
               Print (Part.Content, Errors);

            when Sessions.Done                             =>
               if not Answer.Is_Empty then
                  Print ("Agent: " & Answer, Output);
                  Thread.Append
                    (Threads.Message'
                       (From => Threads.Assistant, Content => Answer));
               end if;
         end case;
      end Show;
   begin
      Thread.Append
        (Threads.Message'(From => Threads.User, Content => Message));
      Sessions.Send (Session, Message, Show'Access);
   end Send;

   procedure Simulate is
      Sequence : constant Wide_Wide_String :=
        Natural'Wide_Wide_Image (Agents.Received (Agent) + 1);
      Event    : constant Signals.Agent_Event :=
        (Identifier  => "simulation" & To_Virtual_String (Sequence),
         Source      => Signals.Simulator,
         Kind        => Signals.Continuous_Integration_Failed,
         Sender      => (Login => "workshop", Is_Bot => False),
         Subject     => "ci:main",
         Title       => "Continuous integration failed on main",
         Description => "Demonstration signal",
         URL         => Empty_Virtual_String,
         Occurred_At => Clocks.Now (Clock));
   begin
      Agents.Ingest (Agent, Event);
      Print (Event.Title & " [" & Event.Subject & "]", Output);

      Print
        ("Received"
         & To_Virtual_String
             (Natural'Wide_Wide_Image (Agents.Received (Agent)))
         & ". The pipeline is an exercise for step-3.",
         Output);
   end Simulate;

   procedure Show_Thread is
      procedure Show_Message (Item : Threads.Message);
      --  Display one thread entry with its author.

      procedure Show_Message (Item : Threads.Message) is
      begin
         Print
           (To_Virtual_String (Item.From'Wide_Wide_Image)
            & ": "
            & Item.Content,
            Output);
      end Show_Message;
   begin
      if Thread.Is_Empty then
         Print ("The main thread is empty.", Output);
      else
         Thread.Iterate (Show_Message'Access);
      end if;
   end Show_Thread;
begin
   VSS.Command_Line.Add_Help_Option;
   VSS.Command_Line.Process;

   Print
     ("Ambient Agents step-0. Type a message or /simulate, /thread,"
      & " /reset, /quit.",
      Output);

   declare
      Line : Virtual_String;
   begin
      loop
         if C_Streams.fflush (C_Streams.stdout) /= 0 then
            raise Ada.IO_Exceptions.Device_Error
              with "Flushing standard output failed";
         end if;

         exit when not Read_Line (Line);

         if Line = "/quit" then
            exit;
         elsif Line = "/simulate" then
            Simulate;
         elsif Line = "/thread" then
            Show_Thread;
         elsif Line = "/reset" then
            Sessions.Reset (Session);
            Agents.Reset (Agent);
            Thread.Clear;
            Print ("Session reset.", Output);
         elsif not Line.Is_Empty then
            Send (Line);
         end if;
      end loop;
   end;
end Ambient_Agents.Run;
