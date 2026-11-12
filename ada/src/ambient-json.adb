with Ambient.Support;
--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with VSS.JSON.Pull_Readers.Simple;
with VSS.JSON.Push_Writers;
with VSS.JSON.Streams;
with VSS.Text_Streams.Memory_UTF8_Input;
with VSS.Text_Streams.Memory_UTF8_Output;
with ACP.Types.Inputs;
with ACP.Types.Outputs;

package body Ambient.JSON is
   use all type VSS.JSON.Streams.JSON_Stream_Element_Kind;
   use type VSS.JSON.JSON_Number_Kind;
   use type VSS.Strings.Virtual_String;

   function Parse
     (Data : VSS.Stream_Element_Vectors.Stream_Element_Vector;
      Item : out Value) return Boolean
   is
      Stream  :
        aliased VSS.Text_Streams.Memory_UTF8_Input.Memory_UTF8_Input_Stream;
      Reader  : VSS.JSON.Pull_Readers.Simple.JSON_Simple_Pull_Reader;
      Raw     : ACP.Types.AgentResponse;
      Success : Boolean := True;
   begin
      Item.Clear;
      Stream.Set_Data (Data);
      Reader.Set_Stream (Stream'Unchecked_Access);
      Reader.Read_Next;
      if not Reader.Is_Start_Document then
         return False;
      end if;
      Reader.Read_Next;
      ACP.Types.Inputs.Input_AgentResponse (Reader, Raw, Success);
      if not Success or else not Reader.Is_End_Document then
         return False;
      end if;
      for Event of Raw loop
         Item.Append (Event);
      end loop;
      return True;
   end Parse;

   function Encode
     (Item : Value'Class)
      return VSS.Stream_Element_Vectors.Stream_Element_Vector
   is
      Stream :
        aliased VSS.Text_Streams.Memory_UTF8_Output.Memory_UTF8_Output_Stream;
      Writer : VSS.JSON.Push_Writers.JSON_Simple_Push_Writer;
      Raw    : ACP.Types.AgentResponse;
   begin
      for Event of Item loop
         Raw.Append (Event);
      end loop;
      Writer.Set_Stream (Stream'Unchecked_Access);
      Writer.Start_Document;
      ACP.Types.Outputs.Output_AgentResponse (Writer, Raw);
      Writer.End_Document;
      if not Writer.Error_Message.Is_Empty then
         raise Program_Error with "cannot encode JSON";
      end if;
      return Stream.Buffer;
   end Encode;

   function Is_Object (Item : Value'Class) return Boolean
   is (not Item.Is_Empty and then Item.First_Element.Kind = Start_Object);
   function Is_String (Item : Value'Class) return Boolean
   is (not Item.Is_Empty
       and then Item.First_Element.Kind = VSS.JSON.Streams.String_Value);
   function Is_Integer (Item : Value'Class) return Boolean
   is (not Item.Is_Empty
       and then Item.First_Element.Kind = Number_Value
       and then Item.First_Element.Number_Value.Kind = VSS.JSON.JSON_Integer);
   function Is_Boolean (Item : Value'Class) return Boolean
   is (not Item.Is_Empty and then Item.First_Element.Kind = Boolean_Value);
   function Is_Array (Item : Value'Class) return Boolean
   is (not Item.Is_Empty and then Item.First_Element.Kind = Start_Array);

   function Text (Item : Value'Class) return VSS.Strings.Virtual_String
   is (if Is_String (Item)
       then Item.First_Element.String_Value
       else VSS.Strings.Empty_Virtual_String);
   function Text
     (Item : Value'Class; Name : VSS.Strings.Virtual_String)
      return VSS.Strings.Virtual_String
   is (Text (Member (Item, Name)));

   function Member
     (Item : Value'Class; Name : VSS.Strings.Virtual_String) return Value
   is
      use ACP.Types.JSON_Event_Lists;
      Position : Cursor := Item.First;
      Result   : Value;
      Found    : Boolean := False;
   begin
      if not Is_Object (Item) then
         return Result;
      end if;
      Next (Position);
      while Has_Element (Position) and then Element (Position).Kind = Key_Name
      loop
         declare
            Selected : constant Boolean := Element (Position).Key_Name = Name;
            Depth    : Natural := 0;
         begin
            if Selected and Found then
               Result.Clear;
               return Result;
            end if;
            Found := Found or Selected;
            Next (Position);
            loop
               declare
                  Event : constant VSS.JSON.Streams.JSON_Stream_Element :=
                    Element (Position);
               begin
                  if Selected then
                     Result.Append (Event);
                  end if;
                  case Event.Kind is
                     when Start_Object | Start_Array =>
                        Depth := Depth + 1;

                     when End_Object | End_Array     =>
                        Depth := Depth - 1;

                     when others                     =>
                        null;
                  end case;
               end;
               Next (Position);
               exit when Depth = 0;
            end loop;
         end;
      end loop;
      return Result;
   end Member;

   function Element (List : Value'Class; Index : Positive) return Value is
      use ACP.Types.JSON_Event_Lists;
      Position : Cursor := List.First;
      Current  : Natural := 0;
      Result   : Value;
   begin
      if List.Is_Empty or else List.First_Element.Kind /= Start_Array then
         return Result;
      end if;
      Next (Position);
      while Has_Element (Position)
        and then ACP.Types.JSON_Event_Lists.Element (Position).Kind
                 /= End_Array
      loop
         Current := Current + 1;
         declare
            Depth : Natural := 0;
         begin
            loop
               declare
                  Event : constant VSS.JSON.Streams.JSON_Stream_Element :=
                    ACP.Types.JSON_Event_Lists.Element (Position);
               begin
                  if Current = Index then
                     Result.Append (Event);
                  end if;
                  case Event.Kind is
                     when Start_Object | Start_Array =>
                        Depth := Depth + 1;

                     when End_Object | End_Array     =>
                        Depth := Depth - 1;

                     when others                     =>
                        null;
                  end case;
               end;
               Next (Position);
               exit when Depth = 0;
            end loop;
         end;
         if Current = Index then
            return Result;
         end if;
      end loop;
      return Result;
   end Element;

   function Object_Value return Value is
      Result : Value;
   begin
      Result.Append ((Kind => Start_Object));
      Result.Append ((Kind => End_Object));
      return Result;
   end Object_Value;

   function Array_Value return Value is
      Result : Value;
   begin
      Result.Append ((Kind => Start_Array));
      Result.Append ((Kind => End_Array));
      return Result;
   end Array_Value;

   function String_Value (Item : VSS.Strings.Virtual_String) return Value is
      Result : Value;
   begin
      Result.Append ((VSS.JSON.Streams.String_Value, Item));
      return Result;
   end String_Value;

   function Integer_Value (Item : ACP.Types.Integer_64) return Value is
      Result : Value;
   begin
      Result.Append
        ((Number_Value,
          (Kind          => VSS.JSON.JSON_Integer,
           Integer_Value => Item,
           others        => <>)));
      return Result;
   end Integer_Value;

   function Null_Value return Value is
      Result : Value;
   begin
      Result.Append ((Kind => VSS.JSON.Streams.Null_Value));
      return Result;
   end Null_Value;

   procedure Add
     (Object : in out Value'Class;
      Name   : VSS.Strings.Virtual_String;
      Item   : Value'Class) is
   begin
      Object.Delete_Last;
      Object.Append ((Key_Name, Name));
      for Event of Item loop
         Object.Append (Event);
      end loop;
      Object.Append ((Kind => End_Object));
   end Add;

   procedure Append (List : in out Value'Class; Item : Value'Class) is
   begin
      List.Delete_Last;
      for Event of Item loop
         List.Append (Event);
      end loop;
      List.Append ((Kind => End_Array));
   end Append;

   function Request
     (Identifier : Value; Method : VSS.Strings.Virtual_String; Params : Value)
      return Value
   is
      Result : Value := Object_Value;
   begin
      Add (Result, "jsonrpc", String_Value ("2.0"));
      if not Identifier.Is_Empty then
         Add (Result, "id", Identifier);
      end if;
      Add (Result, "method", String_Value (Method));
      Add (Result, "params", Params);
      return Result;
   end Request;

   function Response (Identifier : Value; Result : Value) return Value is
      Message : Value := Object_Value;
   begin
      Add (Message, "jsonrpc", String_Value ("2.0"));
      Add (Message, "id", Identifier);
      Add (Message, "result", Result);
      return Message;
   end Response;

   function Error_Response
     (Identifier : Value;
      Code       : ACP.Types.Integer_64;
      Message    : VSS.Strings.Virtual_String;
      Data       : Value := Object_Value) return Value
   is
      Result : Value := Object_Value;
      Error  : Value := Object_Value;
   begin
      Add (Error, "code", Integer_Value (Code));
      Add (Error, "message", String_Value (Message));
      Add (Error, "data", Data);
      Add (Result, "jsonrpc", String_Value ("2.0"));
      Add
        (Result,
         "id",
         (if Identifier.Is_Empty then Null_Value else Identifier));
      Add (Result, "error", Error);
      return Result;
   end Error_Response;
   function Parse (Text : String) return Value is
      Result : Value;
   begin
      if not Parse (Support.Bytes (Text), Result) then
         raise Constraint_Error with "invalid JSON";
      end if;
      return Result;
   end Parse;
   function Encode (Item : Value'Class) return String
   is (Support.Text (Encode (Item)));
   function Get (Item : Value'Class; Name : String) return Value
   is (Member (Item, Support.To_Virtual_String (Name)));
   function To_JSON_String (Text : String) return Value
   is (String_Value (Support.To_Virtual_String (Text)));
   function To_JSON_Integer (Number : Long_Long_Integer) return Value
   is (Integer_Value (ACP.Types.Integer_64 (Number)));
   function To_JSON_Number (Number : Long_Float) return Value
   is (Parse (Number'Image));
   function To_JSON_Boolean (Flag : Boolean) return Value
   is (Parse (if Flag then "true" else "false"));
   function Get_Text (Item : Value'Class; Name : String := "") return String
   is (Support.To_UTF_8_String
         (Text (if Name = "" then Value (Item) else Get (Item, Name))));
   function Get_Integer
     (Item    : Value'Class;
      Name    : String := "";
      Default : Long_Long_Integer := 0) return Long_Long_Integer
   is
      Selected : constant Value :=
        (if Name = "" then Value (Item) else Get (Item, Name));
   begin
      return
        (if Is_Integer (Selected)
         then
           Long_Long_Integer
             (Selected.First_Element.Number_Value.Integer_Value)
         else Default);
   end Get_Integer;
   function Get_Number
     (Item : Value'Class; Name : String := ""; Default : Long_Float := 0.0)
      return Long_Float
   is
      Selected : constant Value :=
        (if Name = "" then Value (Item) else Get (Item, Name));
   begin
      if Selected.Is_Empty or else Selected.First_Element.Kind /= Number_Value
      then
         return Default;
      end if;
      return Long_Float'Value (Encode (Selected));
   end Get_Number;
   function Get_Boolean
     (Item : Value'Class; Name : String := ""; Default : Boolean := False)
      return Boolean
   is
      Selected : constant Value :=
        (if Name = "" then Value (Item) else Get (Item, Name));
   begin
      return
        (if Selected.Is_Empty
           or else Selected.First_Element.Kind /= Boolean_Value
         then Default
         else Selected.First_Element.Boolean_Value);
   end Get_Boolean;
   function Length (List : Value'Class) return Natural is
      Result : Natural := 0;
      Depth  : Natural := 0;
   begin
      if List.Is_Empty or else List.First_Element.Kind /= Start_Array then
         return 0;
      end if;
      for Event of List loop
         if Depth = 1 and then Event.Kind /= End_Array then
            Result := Result + 1;
         end if;
         case Event.Kind is
            when Start_Object | Start_Array =>
               Depth := Depth + 1;

            when End_Object | End_Array     =>
               Depth := Depth - 1;

            when others                     =>
               null;
         end case;
      end loop;
      return Result;
   end Length;
   function Make_Object (Fields : Field_Array) return Value is
      Result : Value := Object_Value;
   begin
      for F of Fields loop
         Add (Result, F.Name, F.Item);
      end loop;
      return Result;
   end Make_Object;
   function Make_Array (Items : Value_Array) return Value is
      Result : Value := Array_Value;
   begin
      for Item of Items loop
         Append (Result, Item);
      end loop;
      return Result;
   end Make_Array;
   function Member_Names (Item : Value) return Value is
      Result : Value := Array_Value;
      Depth  : Natural := 0;
   begin
      for Event of Item loop
         if Event.Kind = Key_Name and Depth = 1 then
            Append (Result, String_Value (Event.Key_Name));
         end if;
         case Event.Kind is
            when Start_Object | Start_Array =>
               Depth := Depth + 1;

            when End_Object | End_Array     =>
               Depth := Depth - 1;

            when others                     =>
               null;
         end case;
      end loop;
      return Result;
   end Member_Names;
   procedure Put (Item : in out Value; Name : String; Data : Value) is
      Depth  : Natural := 0;
      Result : Value := Object_Value;
   begin
      for Event of Item loop
         if Event.Kind = Key_Name and then Depth = 1 then
            if Event.Key_Name /= Support.To_Virtual_String (Name) then
               Add (Result, Event.Key_Name, Member (Item, Event.Key_Name));
            end if;
         end if;
         case Event.Kind is
            when Start_Object | Start_Array =>
               Depth := Depth + 1;

            when End_Object | End_Array     =>
               Depth := Depth - 1;

            when others                     =>
               null;
         end case;
      end loop;
      Add (Result, Support.To_Virtual_String (Name), Data);
      Item := Result;
   end Put;
end Ambient.JSON;
