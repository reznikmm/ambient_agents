--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Ambient_Agents.Clocks is

   procedure Advance (Self : in out Clock; By : Duration) is
   begin
      Self.Offset := Self.Offset + By;
   end Advance;

end Ambient_Agents.Clocks;
