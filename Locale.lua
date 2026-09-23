local _, addon = ...

addon.L = {
    ADDON_NAME = "Clean Binds",
    ACTION_BAR = "Action Bar %d",
    MAIN_ACTION_BAR = "Action Bar",
    PET_BAR = "Pet Bar",
    STANCE_BAR = "Stance / Form Bar",
    POSSESS_BAR = "Possess Bar",
    OVERRIDE_BAR = "Vehicle / Override Bar",
    LOADING = "Waiting for the game to finish loading.",
    READY = "Foundation loaded (WoW %s, build %s, Interface %d).",
    FOUNDATION_ONLY = "Settings and label overrides are not implemented yet.",
    BAR_STATUS = "%s: %d/%d buttons available.",
    BAR_UNAVAILABLE = "%s: not currently available.",
    STARTUP_FAILED = "Could not start: %s",
    UNSUPPORTED_INTERFACE = "Interface %s is unsupported; expected 16001.",
    MISSING_API = "The required API %s is unavailable.",
    INVALID_DATABASE = "Saved data is invalid (%s). Existing data was kept.",
    UNSUPPORTED_SCHEMA = "Saved data has an unsupported schema. Existing data was kept.",
    USAGE = "Usage: /cleanbinds [status]",
}
