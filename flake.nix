{
  description = "A very basic flake";
  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSystem =
        config:
        builtins.listToAttrs (
          map (
            system:
            let
              pkgs = import nixpkgs { inherit system; };
            in
            {
              name = system;
              value = config { inherit system pkgs; };
            }
          ) systems
        );
    in
    {
      packages = forEachSystem (
        { system, pkgs }:
        {
          default = self.packages.${system}.cfddns-middleware;
          cfddns-middleware =
            let
              py = pkgs.python3Packages;

              cloudflare = py.buildPythonPackage {
                pname = "cloudflare";
                version = "2.19.4";
                pyproject = true;
                build-system = [
                  py.setuptools
                  py.wheel
                ];

                propagatedBuildInputs = [
                  py.requests
                  py.pyyaml
                  py.jsonlines
                ];

                src = py.fetchPypi {
                  pname = "cloudflare";
                  version = "2.19.4";
                  sha256 = "sha256-O2AAoBojfCO8z99tICVupREex0qCaunnT58OW7WyOD8=";
                };
              };
            in
            py.buildPythonApplication {
              pname = "cloudflare-dyndns";
              version = "unstable-2025-10-18";
              format = "other";
              src = ./.;

              propagatedBuildInputs = [
                cloudflare
                py.requests
                py.flask
                py.waitress
              ];

              installPhase = ''
                mkdir -p $out/bin
                echo "#!${pkgs.python3.interpreter}" > $out/bin/cloudflare-dyndns
                cat app.py >> $out/bin/cloudflare-dyndns
                chmod +x $out/bin/cloudflare-dyndns
              '';

              meta = {
                description = "Cloudflare DynDNS client for FRITZ!Box";
                homepage = "https://github.com/L480/cloudflare-dyndns";
                license = pkgs.lib.licenses.mit;
              };
            };
        }
      );

      nixosModules = {
        default = self.nixosModules.cfddns-middleware;
        cfddns-middleware =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            inherit (lib)
              mkEnableOption
              mkIf
              mkOption
              types
              ;
            cfg = config.services.cfddns;
          in
          {
            options.services.cfddns = {
              enable = mkEnableOption "Enable the CFDDNS Middleware service";
              port = mkOption {
                type = types.port;
                default = 80;
              };
            };

            config = mkIf cfg.enable {
              systemd.services.cfddns = {
                description = "Cloudflare Dyn DNS Middleware Server";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];
                serviceConfig = {
                  Type = "simple";
                  ExecStart = "${
                    self.packages.${pkgs.stdenv.hostPlatform.system}.cfddns-middleware
                  }/bin/cloudflare-dyndns --port ${toString cfg.port}";
                  Restart = "on-failure";
                };
              };
            };
          };
      };
    };
}
