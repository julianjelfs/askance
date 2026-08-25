/// Stamped by `make deploy-web` (and any build that passes the define) so a
/// device can prove which build it is running — service workers apply
/// updates one open late, and guessing wastes everyone's evening.
const String kBuildStamp = String.fromEnvironment(
  'BUILD_STAMP',
  defaultValue: 'dev',
);
