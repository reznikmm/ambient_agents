--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with VSS.JSON.Content_Handlers;
with VSS.JSON.Pull_Readers;
with Ambient.JSON;

generic
   type Value_Type is private;
   with
     procedure Input
       (Reader  : in out VSS.JSON.Pull_Readers.JSON_Pull_Reader'Class;
        Value   : out Value_Type;
        Success : in out Boolean);
   with
     procedure Output
       (Handler : in out VSS.JSON.Content_Handlers.JSON_Content_Handler'Class;
        Value   : Value_Type);
package Ambient.Codecs is
   function Decode
     (Item : Ambient.JSON.Value; Value : out Value_Type) return Boolean;
   function Encode (Value : Value_Type) return Ambient.JSON.Value;
end Ambient.Codecs;
