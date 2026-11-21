--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Latin_1;
with Ada.IO_Exceptions;
with Ada.Streams;
with Ada.Strings.Unbounded;

with GNAT.Expect;
with GNAT.OS_Lib;

with VSS.Strings.Conversions;

package body Ambient_Agents.HTTP_Requests is

   overriding
   procedure Post
     (Self          : in out HTTP_Request;
      URL           : VSS.IRIs.IRI;
      Content_Type  : VSS.Strings.Virtual_String;
      Authorization : VSS.Strings.Virtual_String;
      Output        : VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Response      : out VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Status_Code   : out Natural)
   is
      pragma Unreferenced (Self);

      use Ada.Characters.Latin_1;
      use Ada.Strings.Unbounded;
      use VSS.Strings.Conversions;
      use type VSS.Strings.Virtual_String;

      Config : Unbounded_String;

      procedure Add_Option (Name, Value : String);
      --  Write one quoted curl config option to pass over standard input.

      function Transfer return String;
      --  Return the response body with the three-digit HTTP status appended.

      procedure Add_Option (Name, Value : String) is
      begin
         Append (Config, Name & " = """);

         for Byte of Value loop
            case Byte is
               when '\' | '"' =>
                  Append (Config, '\');
                  Append (Config, Byte);

               when LF        =>
                  Append (Config, "\n");

               when CR        =>
                  Append (Config, "\r");

               when HT        =>
                  Append (Config, "\t");

               when others    =>
                  Append (Config, Byte);
            end case;
         end loop;

         Append (Config, '"');
         Append (Config, LF);
      end Add_Option;

      function Transfer return String is
         Args   : GNAT.OS_Lib.Argument_List_Access :=
           GNAT.OS_Lib.Argument_String_To_List
             ("--disable --silent --globoff --proto =http,https"
              & " --connect-timeout 10 --max-time 180"
              & " --write-out %{http_code} --config -");
         Status : aliased Integer;
      begin
         declare
            Data : constant String :=
              GNAT.Expect.Get_Command_Output
                ("curl", Args.all, To_String (Config), Status'Access);
         begin
            if Status /= 0 then
               raise Ada.IO_Exceptions.Device_Error
                 with
                   "Posting to CHAT_COMPLETIONS_URL (curl exit code"
                   & Status'Image
                   & ")";
            end if;

            GNAT.OS_Lib.Free (Args);
            return Data;
         end;
      exception
         when GNAT.Expect.Invalid_Process =>
            GNAT.OS_Lib.Free (Args);
            raise Ada.IO_Exceptions.Device_Error
              with "Could not start curl for the Chat Completions request";

         when others =>
            GNAT.OS_Lib.Free (Args);
            raise;
      end Transfer;

      Body_Bytes : String (1 .. Natural (Output.Length));
   begin
      Add_Option ("url", To_UTF_8_String (URL.To_Virtual_String));
      Add_Option ("header", "Content-Type: " & To_UTF_8_String (Content_Type));

      if not Authorization.Is_Empty and then Authorization /= "Bearer " then
         declare
            Header : constant String := To_UTF_8_String (Authorization);
         begin
            if (for some Byte of Header => Byte in CR | LF | NUL) then
               raise Ada.IO_Exceptions.Data_Error
                 with "CHAT_COMPLETIONS_API_KEY contains an invalid byte";
            end if;

            Add_Option ("header", "Authorization: " & Header);
         end;
      end if;

      for Index in Body_Bytes'Range loop
         Body_Bytes (Index) :=
           Character'Val (Output (Ada.Streams.Stream_Element_Offset (Index)));
      end loop;

      Add_Option ("data-binary", Body_Bytes);

      declare
         Data : constant String := Transfer;
      begin
         if Data'Length < 3 then
            raise Ada.IO_Exceptions.Data_Error
              with "Missing HTTP status from Chat Completions transport";
         end if;

         Status_Code := Natural'Value (Data (Data'Last - 2 .. Data'Last));
         Response.Set_Capacity
           (Ada.Streams.Stream_Element_Count (Data'Length - 3));

         for Index in Data'First .. Data'Last - 3 loop
            Response.Append (Character'Pos (Data (Index)));
         end loop;
      end;
   end Post;

end Ambient_Agents.HTTP_Requests;
