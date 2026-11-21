--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Calendar;
use type Ada.Calendar.Time;

package Ambient_Agents.Clocks is

   type Clock is private;
   --  A wall clock with an adjustable offset for workshop simulations.

   function Now (Self : Clock) return Ada.Calendar.Time;
   --  Return the current wall time adjusted by this clock's offset.

   procedure Advance (Self : in out Clock; By : Duration);
   --  Add By seconds to the offset used by Now.

private

   type Clock is record
      Offset : Duration := 0.0;
   end record;

   function Now (Self : Clock) return Ada.Calendar.Time
   is (Ada.Calendar.Clock + Self.Offset);

end Ambient_Agents.Clocks;
