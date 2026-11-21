--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Ada.Calendar;
with Ada.Containers;

with VSS.Strings;

with Ambient_Agents.Agents;
with Ambient_Agents.Sessions;
with Ambient_Agents.Signals;
with Ambient_Agents.Threads;

package body Test_Init is

   procedure Test_Chat_Stub (Op : in out Trendy_Test.Operation'Class) is
      use Ambient_Agents.Sessions;

      Conversation : Session;
      Parts        : Natural := 0;

      procedure Check (Part : Chat_Part);

      procedure Check (Part : Chat_Part) is
      begin
         Parts := @ + 1;

         case Parts is
            when 1      =>
               Op.Assert (Part.Kind = Text);

               if Part.Kind = Text then
                  Op.Assert
                    (Part.Content.Ends_With ("See prompts/step-1.md."));
               end if;

            when 2      =>
               Op.Assert (Part.Kind = Done);

            when others =>
               Op.Assert (Parts <= 2);
         end case;
      end Check;
   begin
      Op.Register (Parallelize => False);
      Send (Conversation, "Hello", Check'Access);
      Op.Assert (Parts = 2);
      Reset (Conversation);
      Parts := 0;
      Send (Conversation, "Hello again", Check'Access);
      Op.Assert (Parts = 2);
   end Test_Chat_Stub;

   procedure Test_Ingest_And_Reset (Op : in out Trendy_Test.Operation'Class) is
      use Ambient_Agents.Agents;
      use Ambient_Agents.Signals;
      use type Ada.Calendar.Time;
      use type Ada.Containers.Count_Type;
      use type VSS.Strings.Virtual_String;

      State : Agent;
      Stamp : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (2026, 1, 1);
      Event : Agent_Event :=
        (Identifier  => "first",
         Source      => Simulator,
         Kind        => Continuous_Integration_Failed,
         Sender      => (Login => "workshop", Is_Bot => False),
         Subject     => "ci:main",
         Title       => "CI failed",
         Occurred_At => Stamp,
         others      => <>);
   begin
      Op.Register (Parallelize => False);
      Op.Assert (Received (State) = 0);
      Op.Assert (Recent_Events (State).Is_Empty);

      Ingest (State, Event);
      Op.Assert (Received (State) = 1);
      Op.Assert (Recent_Events (State).First_Element = Event);

      Event.Identifier := "repeat";

      for Index in 2 .. 60 loop
         Ingest (State, Event);
      end loop;

      Event.Identifier := "last";
      Ingest (State, Event);

      declare
         Recent : constant Event_Vectors.Vector := Recent_Events (State);
      begin
         Op.Assert (Received (State) = 61);
         Op.Assert (Recent.Length = 60);
         Op.Assert (Recent.First_Element.Identifier = "repeat");
         Op.Assert (Recent.Last_Element.Identifier = "last");
         Op.Assert (Recent.Last_Element.Occurred_At = Stamp);
      end;

      Reset (State);
      Op.Assert (Received (State) = 0);
      Op.Assert (Recent_Events (State).Is_Empty);
   end Test_Ingest_And_Reset;

   procedure Test_Thread (Op : in out Trendy_Test.Operation'Class) is
      use Ambient_Agents.Threads;

      History  : Thread;
      Position : Natural := 0;
      Expected : constant array (1 .. 3) of Message :=
        [(From => User, Content => "Hello"),
         (From => Assistant, Content => "Welcome"),
         (From => Report, Content => "Build passed")];

      procedure Check (Item : Message);

      procedure Check (Item : Message) is
      begin
         Position := @ + 1;
         Op.Assert (Position in Expected'Range);
         Op.Assert (Item = Expected (Position));
      end Check;
   begin
      Op.Register (Parallelize => False);
      Op.Assert (History.Is_Empty);

      for Item of Expected loop
         History.Append (Item);
      end loop;

      Op.Assert (not History.Is_Empty);
      History.Iterate (Check'Access);
      Op.Assert (Position = Expected'Length);

      History.Clear;
      Op.Assert (History.Is_Empty);
      Position := 0;
      History.Iterate (Check'Access);
      Op.Assert (Position = 0);
   end Test_Thread;

end Test_Init;
