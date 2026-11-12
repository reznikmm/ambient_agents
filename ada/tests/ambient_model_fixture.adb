--  Offline Chat Completions server: one tool call followed by an answer.
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.Sockets;
with Ambient.JSON;
with Ambient.Support;

procedure Ambient_Model_Fixture is
   use GNAT.Sockets, Ambient.JSON, Ambient.Support;
   use type Ada.Streams.Stream_Element_Offset;
   Listener, Connection : Socket_Type;
   Address              : Sock_Addr_Type;
   CRLF                 : constant String := ASCII.CR & ASCII.LF;
   Port                 : constant Port_Type :=
     Port_Type'Value (Environment ("MODEL_TEST_PORT", "19422"));
   procedure Send (Text : String) is
      Data  : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
      Last  : Ada.Streams.Stream_Element_Offset;
      Start : Ada.Streams.Stream_Element_Offset := 1;
   begin
      for J in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (J - Text'First + 1)) :=
           Character'Pos (Text (J));
      end loop;
      while Start <= Data'Last loop
         Send_Socket (Connection, Data (Start .. Data'Last), Last);
         pragma Assert (Last >= Start);
         Start := Last + 1;
      end loop;
   end Send;
begin
   Create_Socket (Listener);
   Set_Socket_Option (Listener, Socket_Level, (Reuse_Address, True));
   Bind_Socket
     (Listener,
      (Family => Family_Inet, Addr => Inet_Addr ("127.0.0.1"), Port => Port));
   Listen_Socket (Listener);
   for Turn in 1 .. 2 loop
      Accept_Socket (Listener, Connection, Address);
      declare
         Raw                   : Ada.Strings.Unbounded.Unbounded_String;
         Data                  : Ada.Streams.Stream_Element_Array (1 .. 4096);
         Last                  : Ada.Streams.Stream_Element_Offset;
         Header_End, Body_Size : Natural := 0;
         Message               : Value;
         Reply                 : Value;
      begin
         loop
            Receive_Socket (Connection, Data, Last);
            pragma Assert (Last > 0);
            for J in 1 .. Last loop
               Ada.Strings.Unbounded.Append (Raw, Character'Val (Data (J)));
            end loop;
            declare
               Text : constant String := Ada.Strings.Unbounded.To_String (Raw);
            begin
               if Header_End = 0 then
                  Header_End := Ada.Strings.Fixed.Index (Text, CRLF & CRLF);
                  if Header_End > 0 then
                     declare
                        Position : constant Natural :=
                          Ada.Strings.Fixed.Index (Text, "Content-Length:");
                        Final    : constant Natural :=
                          Ada.Strings.Fixed.Index (Text, CRLF, Position);
                     begin
                        Body_Size :=
                          Natural'Value (Text (Position + 15 .. Final - 1));
                     end;
                  end if;
               end if;
               if Header_End > 0
                 and then Text'Length >= Header_End + 3 + Body_Size
               then
                  Append_File
                    (Environment ("MODEL_TEST_LOG"), Text & ASCII.LF);
                  exit;
               end if;
            end;
         end loop;
         if Turn = 1 then
            Message :=
              Make_Object
                ([("role", To_JSON_String ("assistant")),
                  ("content", Null_Value),
                  ("tool_calls",
                   Make_Array
                     ([Make_Object
                         ([("id", To_JSON_String ("call-1")),
                           ("type", To_JSON_String ("function")),
                           ("function",
                            Make_Object
                              ([("name", To_JSON_String ("memory_read")),
                                ("arguments",
                                 To_JSON_String
                                   ("{""path"":""preferences.md""}"))]))])]))]);
         else
            Message :=
              Make_Object
                ([("role", To_JSON_String ("assistant")),
                  ("content",
                   To_JSON_String ("Привіт. I read your preferences."))]);
         end if;
         Reply :=
           Make_Object
             ([("id", To_JSON_String ("offline")),
               ("object", To_JSON_String ("chat.completion")),
               ("created", To_JSON_Integer (0)),
               ("model", To_JSON_String ("offline-model")),
               ("choices",
                Make_Array
                  ([Make_Object
                      ([("index", To_JSON_Integer (0)),
                        ("finish_reason",
                         To_JSON_String
                           (if Turn = 1 then "tool_calls" else "stop")),
                        ("message", Message)])]))]);
         declare
            Text : constant String := Encode (Reply);
         begin
            Send
              ("HTTP/1.1 200 OK"
               & CRLF
               & "Content-Type: application/json"
               & CRLF
               & "Content-Length: "
               & Trim (Text'Length'Image)
               & CRLF
               & "Connection: close"
               & CRLF
               & CRLF
               & Text);
         end;
         Close_Socket (Connection);
      end;
   end loop;
   Close_Socket (Listener);
end Ambient_Model_Fixture;
