with Ambient.Engine;

package Ambient.Server is
   procedure Run
     (Agent     : in out Engine.Agent;
      Port      : Positive;
      Dashboard : Boolean := False);
end Ambient.Server;
