with Ada.Characters.Handling;
with Ada.Directories;
with GNAT.OS_Lib;
with Ambient.Support;

package body Ambient.State is
   use JSON, Support;
   procedure Open (Self : in out Store; Path : String) is
   begin
      Self.Path := To_Virtual_String (Path);
      if Path /= ":memory:" then
         Self.Data := Parse (Read_File (Path, "{}"));
         if not Is_Object (Self.Data) then
            raise Constraint_Error with "invalid state file " & Path;
         end if;
      end if;
   end Open;
   procedure Save (Self : Store) is
      Path    : constant String := To_UTF_8_String (Self.Path);
      Success : Boolean;
   begin
      if Path /= ":memory:" and Path /= "" then
         Write_File (Path & ".tmp", Encode (Self.Data));
         GNAT.OS_Lib.Rename_File (Path & ".tmp", Path, Success);
         if not Success then
            raise Program_Error with "cannot replace state file " & Path;
         end if;
      end if;
   end Save;
   function Get (Self : Store; Key : String) return Value
   is (JSON.Get (Self.Data, Key));
   procedure Set (Self : in out Store; Key : String; Item : Value) is
   begin
      Put (Self.Data, Key, Item);
   end Set;
   procedure Reset (Self : in out Store) is
   begin
      Self.Data := Object_Value;
      Self.Save;
   end Reset;
   function Contents (Self : Store) return Value
   is (Self.Data);
   function File_Path (Self : Store) return String
   is (To_UTF_8_String (Self.Path));
   function Tail (Items : Value; Count : Natural) return Value is
      Result : Value := Array_Value;
      Size   : constant Natural := Length (Items);
   begin
      for J in (if Size > Count then Size - Count + 1 else 1) .. Size loop
         Append (Result, Element (Items, J));
      end loop;
      return Result;
   end Tail;
   function Memory_Index (Root : String) return Value is
      Result : Value := Array_Value;
      procedure Walk (Relative : String) is
         use Ada.Directories;
         Search     : Search_Type;
         Entry_Item : Directory_Entry_Type;
      begin
         if not Exists (Root & "/" & Relative) then
            return;
         end if;
         Start_Search (Search, Root & "/" & Relative, "*");
         while More_Entries (Search) loop
            Get_Next_Entry (Search, Entry_Item);
            declare
               Name : constant String := Simple_Name (Entry_Item);
               Path : constant String :=
                 (if Relative = "" then Name else Relative & "/" & Name);
            begin
               if Name /= "." and Name /= ".." then
                  if Kind (Entry_Item) = Directory
                    and then not GNAT.OS_Lib.Is_Symbolic_Link
                                   (Full_Name (Entry_Item))
                  then
                     if Inside (Root, Path) /= "" then
                        Walk (Path);
                     end if;
                  elsif Kind (Entry_Item) = Ordinary_File
                    and then Contains (Name, ".md")
                    and then Length (Result) < 40
                  then
                     declare
                        Content : constant String :=
                          Read_File (Inside (Root, Path));
                        Lines   : Natural := 0;
                        Last    : Natural := Content'Last;
                     begin
                        for J in Content'Range loop
                           if Content (J) = ASCII.LF then
                              Lines := Lines + 1;
                              if Last = Content'Last then
                                 Last := J - 1;
                              end if;
                           end if;
                        end loop;
                        Append
                          (Result,
                           Make_Object
                             ([("path", To_JSON_String (Path)),
                               ("lines",
                                To_JSON_Integer (Long_Long_Integer (Lines))),
                               ("about",
                                To_JSON_String
                                  (Content (1 .. Natural'Min (Last, 100))))]));
                     end;
                  end if;
               end if;
            end;
         end loop;
         End_Search (Search);
      end Walk;
   begin
      Walk ("");
      return Result;
   end Memory_Index;
   function Watches (Root : String) return Value is
      Content : constant String := Read_File (Root & "/watches.md");
      Result  : Value := Array_Value;
      Start   : Positive := 1;
   begin
      for J in Content'Range loop
         if Content (J) = ASCII.LF or J = Content'Last then
            declare
               Line : constant String :=
                 Trim
                   (Content
                      (Start
                       .. (if Content (J) = ASCII.LF then J - 1 else J)));
            begin
               if Line'Length > 2
                 and then Line (Line'First .. Line'First + 1) = "- "
               then
                  Append
                    (Result,
                     To_JSON_String
                       (Trim (Line (Line'First + 2 .. Line'Last))));
               end if;
            end;
            Start := J + 1;
         end if;
      end loop;
      return Result;
   end Watches;
   procedure Watch (Root : String; What : String; Remove : Boolean := False) is
      use VSS.Strings;
      Items   : constant Value := Watches (Root);
      Content : Virtual_String :=
        To_Virtual_String ("# Watches" & ASCII.LF & ASCII.LF);
      Found   : Boolean := False;
      Match   : constant String :=
        Ada.Characters.Handling.To_Lower (Trim (What));
   begin
      for J in 1 .. Length (Items) loop
         declare
            Line : constant String := Get_Text (Element (Items, J));
            Same : constant Boolean :=
              Ada.Characters.Handling.To_Lower (Line) = Match;
         begin
            Found := Found or Same;
            if not (Same and Remove) then
               Content.Append (To_Virtual_String ("- " & Line & ASCII.LF));
            end if;
         end;
      end loop;
      if not Remove and not Found and Trim (What) /= "" then
         if Contains (What, String'(1 => ASCII.LF))
           or Contains (What, String'(1 => ASCII.CR))
         then
            raise Constraint_Error with "watch must fit on one line";
         end if;
         Content.Append (To_Virtual_String ("- " & Trim (What) & ASCII.LF));
      end if;
      Write_File (Root & "/watches.md", To_UTF_8_String (Content));
   end Watch;
   procedure Remember (Root, Subject, Date_Text, Line : String) is
   begin
      Append_File
        (Inside (Root, "journal/" & Date_Text & ".md"),
         "- " & Subject & ": " & Line & ASCII.LF);
      Append_File
        (Inside (Root, "subjects/" & Slug (Subject) & ".md"),
         "- " & Date_Text & " " & Line & ASCII.LF);
   end Remember;
end Ambient.State;
