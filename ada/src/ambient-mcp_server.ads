with Ambient.Engine;
with Ambient.JSON;

package Ambient.MCP_Server is
   function Process
     (Agent : in out Engine.Agent; Message : JSON.Value) return JSON.Value;
   procedure Run (Agent : in out Engine.Agent);
end Ambient.MCP_Server;
