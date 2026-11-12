with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.OS_Lib;
with VSS.Strings.Conversions;

package body Ambient.Support is
   function To_Virtual_String (Text : String) return VSS.Strings.Virtual_String
   is (VSS.Strings.Conversions.To_Virtual_String (Text));
   function To_UTF_8_String (Text : VSS.Strings.Virtual_String) return String
   is (VSS.Strings.Conversions.To_UTF_8_String (Text));
   function Bytes
     (Text : String) return VSS.Stream_Element_Vectors.Stream_Element_Vector
   is
      Result : VSS.Stream_Element_Vectors.Stream_Element_Vector;
   begin
      for C of Text loop
         Result.Append (Character'Pos (C));
      end loop;
      return Result;
   end Bytes;
   function Text
     (Data : VSS.Stream_Element_Vectors.Stream_Element_Vector) return String
   is
      Result : String (1 .. Integer (Data.Length));
   begin
      for J in Result'Range loop
         Result (J) :=
           Character'Val (Data (Ada.Streams.Stream_Element_Offset (J)));
      end loop;
      return Result;
   end Text;
   function Environment (Name : String; Default : String := "") return String
   is (Ada.Environment_Variables.Value (Name, Default));
   function Trim (Text : String) return String
   is (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));
   function Image (Value : Long_Long_Integer) return String
   is (Trim (Value'Image));
   function Contains (Text : String; Pattern : String) return Boolean
   is (Ada.Strings.Fixed.Index
         (Ada.Characters.Handling.To_Lower (Text),
          Ada.Characters.Handling.To_Lower (Pattern))
       /= 0);
   procedure Log (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Message);
   end Log;
   function Read_File (Path : String; Default : String := "") return String is
      use Ada.Streams;
      File : Stream_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return Default;
      end if;
      Stream_IO.Open (File, Stream_IO.In_File, Path);
      declare
         Data   :
           Stream_Element_Array
             (1 .. Stream_Element_Offset (Stream_IO.Size (File)));
         Last   : Stream_Element_Offset;
         Result : String (1 .. Integer (Data'Length));
      begin
         Stream_IO.Read (File, Data, Last);
         Stream_IO.Close (File);
         for J in Result'Range loop
            Result (J) := Character'Val (Data (Stream_Element_Offset (J)));
         end loop;
         return Result;
      end;
   exception
      when others =>
         if Stream_IO.Is_Open (File) then
            Stream_IO.Close (File);
         end if;
         raise;
   end Read_File;
   procedure Write_File (Path : String; Content : String) is
      use Ada.Streams;
      File : Stream_IO.File_Type;
      Data : Stream_Element_Array (1 .. Content'Length);
   begin
      Ada.Directories.Create_Path
        (Ada.Directories.Containing_Directory (Path));
      Stream_IO.Create (File, Stream_IO.Out_File, Path);
      for J in Content'Range loop
         Data (Stream_Element_Offset (J - Content'First + 1)) :=
           Character'Pos (Content (J));
      end loop;
      Stream_IO.Write (File, Data);
      Stream_IO.Close (File);
   exception
      when others =>
         if Stream_IO.Is_Open (File) then
            Stream_IO.Close (File);
         end if;
         raise;
   end Write_File;
   procedure Append_File (Path : String; Content : String) is
   begin
      Write_File (Path, Read_File (Path) & Content);
   end Append_File;
   function Inside (Root : String; Path : String) return String is
      use GNAT.OS_Lib;
      Base : constant String :=
        Normalize_Pathname (Root, Resolve_Links => True);
      Full : constant String :=
        Normalize_Pathname (Path, Directory => Base, Resolve_Links => True);
   begin
      if Full /= Base
        and then (Full'Length <= Base'Length
                  or else Full (Full'First .. Full'First + Base'Length)
                          /= Base & "/")
      then
         raise Constraint_Error with "path outside " & Root & ": " & Path;
      end if;
      return Full;
   end Inside;
   function Slug (Text : String) return String is
      Result : String (1 .. Text'Length);
      Last   : Natural := 0;
   begin
      for C of Ada.Characters.Handling.To_Lower (Text) loop
         if C in 'a' .. 'z' | '0' .. '9' then
            Last := Last + 1;
            Result (Last) := C;
         elsif Last > 0 and then Result (Last) /= '-' then
            Last := Last + 1;
            Result (Last) := '-';
         end if;
      end loop;
      if Last > 0 and then Result (Last) = '-' then
         Last := Last - 1;
      end if;
      return (if Last = 0 then "misc" else Result (1 .. Last));
   end Slug;
   function Run
     (Program   : String;
      Arguments : VSS.String_Vectors.Virtual_String_Vector;
      Input     : String := "";
      Timeout   : Positive := 30) return String
   is
      use GNAT.OS_Lib;
      Input_Name, Output_Name             : String_Access;
      Input_Descriptor, Output_Descriptor : File_Descriptor := Invalid_FD;
      Status                              : Integer;
      Success                             : Boolean;
      Runner                              : String_Access :=
        Locate_Exec_On_Path ("timeout");
      Process_Arguments                   : Argument_List (1 .. 6);
      procedure Cleanup is
         Deleted : Boolean;
      begin
         if Input_Descriptor /= Invalid_FD then
            Close (Input_Descriptor);
            Input_Descriptor := Invalid_FD;
         end if;
         if Output_Descriptor /= Invalid_FD then
            Close (Output_Descriptor);
            Output_Descriptor := Invalid_FD;
         end if;
         for Argument of Process_Arguments loop
            Free (Argument);
         end loop;
         Free (Runner);
         if Input_Name /= null then
            Delete_File (Input_Name.all, Deleted);
            Free (Input_Name);
         end if;
         if Output_Name /= null then
            Delete_File (Output_Name.all, Deleted);
            Free (Output_Name);
         end if;
      end Cleanup;
   begin
      Create_Temp_File (Input_Descriptor, Input_Name);
      Create_Temp_File (Output_Descriptor, Output_Name);
      if Input_Descriptor = Invalid_FD or Output_Descriptor = Invalid_FD then
         raise Program_Error with "cannot create process files";
      end if;
      if Input'Length > 0
        and then Write (Input_Descriptor, Input'Address, Input'Length)
                 /= Input'Length
      then
         raise Program_Error with "cannot write process input";
      end if;
      Close (Input_Descriptor);
      Input_Descriptor := Invalid_FD;
      Close (Output_Descriptor);
      Output_Descriptor := Invalid_FD;
      Process_Arguments (1) := new String'("--signal=KILL");
      Process_Arguments (2) := new String'(Trim (Timeout'Image));
      Process_Arguments (3) := new String'("bash");
      Process_Arguments (4) := new String'("-c");
      --  Only this constant script is interpreted. All caller values are argv.
      Process_Arguments (5) := new String'("exec ""$@"" < ""$0""");
      Process_Arguments (6) := new String'(Input_Name.all);
      declare
         All_Arguments : Argument_List (1 .. Arguments.Length + 7);
      begin
         All_Arguments (1 .. 6) := Process_Arguments (1 .. 6);
         All_Arguments (7) := new String'(Program);
         for J in 1 .. Arguments.Length loop
            All_Arguments (J + 7) :=
              new String'(To_UTF_8_String (Arguments (J)));
         end loop;
         if Runner = null then
            raise Program_Error with "GNU timeout is required";
         end if;
         Spawn
           (Runner.all,
            All_Arguments,
            Output_Name.all,
            Success,
            Status,
            Err_To_Out => False);
         for J in 7 .. All_Arguments'Last loop
            Free (All_Arguments (J));
         end loop;
      end;
      declare
         Result : constant String := Read_File (Output_Name.all);
      begin
         Cleanup;
         if not Success or else Status /= 0 then
            raise Program_Error
              with Program & " exited " & Trim (Status'Image);
         end if;
         return Result;
      end;
   exception
      when others =>
         Cleanup;
         raise;
   end Run;
end Ambient.Support;
