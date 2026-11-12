--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with VSS.JSON.Pull_Readers.Simple;
with VSS.JSON.Push_Writers;
with VSS.Text_Streams.Memory_UTF8_Input;
with VSS.Text_Streams.Memory_UTF8_Output;

package body Ambient.Codecs is
   function Decode
     (Item : Ambient.JSON.Value; Value : out Value_Type) return Boolean
   is
      Stream  :
        aliased VSS.Text_Streams.Memory_UTF8_Input.Memory_UTF8_Input_Stream;
      Reader  : VSS.JSON.Pull_Readers.Simple.JSON_Simple_Pull_Reader;
      Success : Boolean := True;
   begin
      Stream.Set_Data (Ambient.JSON.Encode (Item));
      Reader.Set_Stream (Stream'Unchecked_Access);
      Reader.Read_Next;
      Reader.Read_Next;
      Input (Reader, Value, Success);
      return Success and then Reader.Is_End_Document;
   end Decode;

   function Encode (Value : Value_Type) return Ambient.JSON.Value is
      Stream :
        aliased VSS.Text_Streams.Memory_UTF8_Output.Memory_UTF8_Output_Stream;
      Writer : VSS.JSON.Push_Writers.JSON_Simple_Push_Writer;
      Result : Ambient.JSON.Value;
   begin
      Writer.Set_Stream (Stream'Unchecked_Access);
      Writer.Start_Document;
      Output (Writer, Value);
      Writer.End_Document;
      if not Writer.Error_Message.Is_Empty
        or else not Ambient.JSON.Parse (Stream.Buffer, Result)
      then
         raise Program_Error with "cannot encode generated protocol value";
      end if;
      return Result;
   end Encode;
end Ambient.Codecs;
