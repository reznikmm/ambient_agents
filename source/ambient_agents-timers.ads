--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Calendar;

with VSS.Strings;

with Ambient_Agents.Signals;

package Ambient_Agents.Timers is

   type Timer_Request is record
      Subject : VSS.Strings.Virtual_String;
      At_Time : Ada.Calendar.Time;
      Reason  : VSS.Strings.Virtual_String;
   end record;
   --  A request to revisit a subject at a specific time.

   type Timer is limited interface;
   --  Schedules follow-ups and turns them into events when they are due.

   procedure Schedule (Self : in out Timer; Request : Timer_Request)
   is abstract;
   --  Register a follow-up for the time in Request.

   function Due
     (Self : in out Timer; Now : Ada.Calendar.Time)
      return Signals.Event_Vectors.Vector
   is abstract;
   --  Return timer events for follow-ups due at or before Now.

end Ambient_Agents.Timers;
