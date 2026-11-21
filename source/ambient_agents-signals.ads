--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Calendar;
with Ada.Containers.Vectors;

with VSS.Strings;

package Ambient_Agents.Signals is

   type Source_Kind is (GitHub, Simulator, Timer);
   --  Origin of an incoming event.

   type Event_Kind is
     (Continuous_Integration_Failed,
      Continuous_Integration_Passed,
      Issue_Opened,
      Issue_Edited,
      Issue_Commented,
      Pull_Request_Opened,
      Pull_Request_Commented,
      Timer_Fired);
   --  Activity observed at the source and normalized for the agent.

   type Signal is (Continuous_Integration, Issues, Pull_Requests);
   --  Category used to route work to a worker session.

   type Actor is record
      Login  : VSS.Strings.Virtual_String;
      Is_Bot : Boolean := False;
   end record;
   --  The account or system that produced an event.

   type Agent_Event is record
      Identifier  : VSS.Strings.Virtual_String;
      Source      : Source_Kind;
      Kind        : Event_Kind;
      Sender      : Actor;
      Subject     : VSS.Strings.Virtual_String;
      Title       : VSS.Strings.Virtual_String;
      Description : VSS.Strings.Virtual_String;
      URL         : VSS.Strings.Virtual_String;
      Occurred_At : Ada.Calendar.Time;
   end record;
   --  The common input from every event source. Subject is the key used
   --  to group related work, such as events about the same issue.

   package Event_Vectors is new Ada.Containers.Vectors (Positive, Agent_Event);

end Ambient_Agents.Signals;
