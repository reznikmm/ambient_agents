with Ada.Exceptions;
with Ada.Text_IO;
with MCP.Types;
with MCP.Types.Inputs;
with MCP.Types.Outputs;
with Ambient.Codecs;
with Ambient.Support;

package body Ambient.MCP_Server is
   use JSON, Support;
   use type MCP.Types.Integer_64;
   Protocol_Version : constant String := "2026-07-28";
   package Requests is new
     Ambient.Codecs
       (MCP.Types.ClientRequest,
        MCP.Types.Inputs.Input_ClientRequest,
        MCP.Types.Outputs.Output_ClientRequest);
   package Discover_Results is new
     Ambient.Codecs
       (MCP.Types.DiscoverResult,
        MCP.Types.Inputs.Input_DiscoverResult,
        MCP.Types.Outputs.Output_DiscoverResult);
   package List_Results is new
     Ambient.Codecs
       (MCP.Types.ListToolsResult,
        MCP.Types.Inputs.Input_ListToolsResult,
        MCP.Types.Outputs.Output_ListToolsResult);
   package Tool_Results is new
     Ambient.Codecs
       (MCP.Types.CallToolResult,
        MCP.Types.Inputs.Input_CallToolResult,
        MCP.Types.Outputs.Output_CallToolResult);
   function Process (Agent : in out Engine.Agent; Message : Value) return Value
   is
      Identifier : constant Value := Get (Message, "id");
      Method     : constant String := Get_Text (Message, "method");
      Metadata   : constant Value := Get (Get (Message, "params"), "_meta");
      Request    : MCP.Types.ClientRequest;
   begin
      if not Is_Object (Message)
        or Get_Text (Message, "jsonrpc") /= "2.0"
        or Method = ""
      then
         return
           Error_Response (Null_Value, -32600, "Invalid JSON-RPC request");
      elsif Identifier.Is_Empty then
         return Identifier;
      elsif not Is_String (Identifier) and not Is_Integer (Identifier) then
         return Error_Response (Null_Value, -32600, "Invalid request id");
      elsif Method not in "server/discover" | "tools/list" | "tools/call" then
         return Error_Response (Identifier, -32601, "Method not found");
      elsif Get_Text (Metadata, "io.modelcontextprotocol/protocolVersion")
        /= Protocol_Version
      then
         return
           Error_Response (Identifier, -32022, "Use MCP protocol 2026-07-28");
      elsif not Is_Object
                  (Get
                     (Metadata, "io.modelcontextprotocol/clientCapabilities"))
      then
         return
           Error_Response
             (Identifier, -32602, "Missing clientCapabilities metadata");
      elsif not Requests.Decode (Message, Request) then
         return Error_Response (Identifier, -32602, "Invalid MCP parameters");
      end if;
      case Request.Union.Kind is
         when MCP.Types.Enum.server_discover =>
            declare
               Result : MCP.Types.DiscoverResult;
            begin
               Result.cacheScope := MCP.Types.Enum.a_private;
               Result.capabilities.tools := (Is_Set => True, Value => <>);
               Result.instructions :=
                 "Ambient agent: repository reads, watches, reminders and Markdown memory.";
               Result.resultType := "complete";
               Result.supportedVersions.Append
                 (To_Virtual_String (Protocol_Version));
               Result.ttlMs := 0;
               return Response (Identifier, Discover_Results.Encode (Result));
            end;

         when MCP.Types.Enum.tools_list      =>
            declare
               Result : MCP.Types.ListToolsResult;
            begin
               Result.cacheScope := MCP.Types.Enum.a_private;
               Result.resultType := "complete";
               Result.ttlMs := 0;
               Result.tools := Engine.Tool_List;
               return Response (Identifier, List_Results.Encode (Result));
            end;

         when MCP.Types.Enum.tools_call      =>
            declare
               Parameters : constant MCP.Types.CallToolRequestParams :=
                 Request.Union.tools_call.params;
               Result     : MCP.Types.CallToolResult;
               Block      : MCP.Types.ContentBlock;
               Arguments  : Value;
               Catalog    : constant MCP.Types.Tool_Vector := Engine.Tool_List;
               Found      : Boolean := False;
            begin
               for J in 1 .. Catalog.Length loop
                  if To_UTF_8_String (Catalog (J).name)
                    = To_UTF_8_String (Parameters.name)
                  then
                     Found := True;
                  end if;
               end loop;
               if not Found then
                  return Error_Response (Identifier, -32602, "Unknown tool");
               end if;
               for Event of Parameters.arguments loop
                  Arguments.Append (Event);
               end loop;
               if Arguments.Is_Empty then
                  Arguments := Object_Value;
               end if;
               Result.resultType := "complete";
               Block.Union := (Kind => MCP.Types.Enum.text, others => <>);
               begin
                  Block.Union.text.text :=
                    To_Virtual_String
                      (Agent.Execute_Tool
                         (To_UTF_8_String (Parameters.name), Arguments));
               exception
                  when Error : others =>
                     Result.isError := True;
                     Block.Union.text.text :=
                       To_Virtual_String
                         (Ada.Exceptions.Exception_Message (Error));
               end;
               Result.content.Append (Block);
               return Response (Identifier, Tool_Results.Encode (Result));
            end;

         when others                         =>
            return Error_Response (Identifier, -32601, "Method not found");
      end case;
   end Process;
   procedure Run (Agent : in out Engine.Agent) is
   begin
      while not Ada.Text_IO.End_Of_File loop
         declare
            Line  : constant String := Ada.Text_IO.Get_Line;
            Reply : Value;
         begin
            begin
               if Line'Length > 1_048_576 then
                  raise Constraint_Error with "MCP message exceeds 1 MiB";
               end if;
               Reply := Process (Agent, Parse (Line));
            exception
               when Error : others =>
                  Log ("MCP: " & Ada.Exceptions.Exception_Message (Error));
                  Reply := Error_Response (Null_Value, -32700, "Parse error");
            end;
            if not Reply.Is_Empty then
               Ada.Text_IO.Put_Line (Encode (Reply));
               Ada.Text_IO.Flush;
            end if;
            Agent.Tick;
            Agent.Flush;
         end;
      end loop;
   end Run;
end Ambient.MCP_Server;
