{ config, lib, pkgs, ... }:
with lib;
let cfg = config.services.pleroma-ebooks;
in {
  options.services.pleroma-ebooks.bots = let
    botOpts = { name, ... }:
      let botCfg = cfg.${name};
      in {
        options = {
          accessTokenFile = mkOption {
            description = ''
              Path to access token file.

              You can generate one here: https://tools.splat.soy/pleroma-access-token
            '';
            type = types.str;
            default = "/var/lib/secrets/pleroma-ebooks/${name}";
          };

          dbPath = mkOption {
            description = "Path to store the database";
            type = types.str;
            default = "/var/lib/pleroma-ebooks/${name}";
          };

          site = mkOption {
            description = "Site to post on";
            type = types.str;
          };

          fetchOnCalendar = mkOption {
            description =
              "How often to fetch. See systemd.time(7) for more information about the format.";
            type = types.str;
            default = "hourly";
          };

          postOnCalendar = mkOption {
            description =
              "How often to post. See systemd.time(7) for more information about the format.";
            type = types.str;
            default = "hourly";
          };

          extraConfig = mkOption {
            description = ''
              Additional options to add to the config.

              See the default config for more details: https://github.com/ioistired/pleroma-ebooks/blob/master/config.defaults.json
            '';
            type = types.attrs;
            default = {
              cw = null;
              learn_from_cw = false;
              ignored_cws = [ ];
              mention_handling = 1;
              max_thread_length = 15;
              strip_paired_punctuation = false;
              limit_length = false;
              length_lower_limit = 5;
              length_upper_limit = 50;
              overlap_ratio_enabled = false;
              overlap_ratio = 0.7;
              generation_mode = "markov";
            };
          };

          config = mkOption {
            description = ''
              The config to write in, minus the access_token attribute. You should use `extraConfig` and the other attributes instead.

              See the default config for more details: https://github.com/ioistired/pleroma-ebooks/blob/master/config.defaults.json
            '';
            type = types.attrs;
            default = {
              site = botCfg.site;
              db_path = botCfg.dbPath;
            } // botCfg.extraConfig;
          };
        };
      };

  in mkOption {
    type = with types; attrsOf (submodule botOpts);
    default = { };
    description = ''
      Bots to run. If none are defined then this module is disabled.
    '';
  };

  config = mkMerge (mapAttrsToList (name: botCfg:
    let
      unitName = "pleroma-ebooks-${name}";
      baseConfigJSON = pkgs.writeText "pleroma-ebooks-${name}-config.json"
        (builtins.toJSON botCfg.config);
      generate-pleroma-ebooks-config = pkgs.writeShellApplication {
        name = "generate-pleroma-ebooks-config";
        runtimeInputs = with pkgs; [ coreutils jq pleroma-ebooks ];
        text = ''
          config="$(mktemp)"
          chmod 600 "$config"

          access_token="$(cat "$ACCESS_TOKEN_FILE")"
          jq --arg token "$access_token" '. + {access_token: $token}' < "$BASE_CONFIG_FILE" > "$config"

          echo "$config"
        '';
      };
    in {
      systemd.services."${unitName}-post" = {
        wantedBy = [ "network-online.target" ];
        path = with pkgs; [ generate-pleroma-ebooks-config pleroma-ebooks ];
        environment = {
          ACCESS_TOKEN_FILE = botCfg.accessTokenFile;
          BASE_CONFIG_FILE = baseConfigJSON;
        };
        unitConfig.ConditionPathExists = botCfg.accessTokenFile;
        script = ''
          config="$(generate-pleroma-ebooks-config)"
          gen.py -c "$config"
          rm "$config"
        '';
      };
      systemd.timers."${unitName}-post" = {
        wantedBy = [ "network-online.target" ];
        timerConfig.OnCalendar = botCfg.postOnCalendar;
      };

      systemd.services."${unitName}-fetch" = {
        wantedBy = [ "network-online.target" ];
        path = with pkgs; [ generate-pleroma-ebooks-config pleroma-ebooks ];
        environment = {
          ACCESS_TOKEN_FILE = botCfg.accessTokenFile;
          BASE_CONFIG_FILE = baseConfigJSON;
        };
        unitConfig.ConditionPathExists = botCfg.accessTokenFile;
        script = ''
          config="$(generate-pleroma-ebooks-config)"
          fetch-posts.py -c "$config"
          rm "$config"
        '';
      };
      systemd.timers."${unitName}-fetch" = {
        wantedBy = [ "network-online.target" ];
        timerConfig.OnCalendar = botCfg.fetchOnCalendar;
      };
    }) cfg.bots);
}

