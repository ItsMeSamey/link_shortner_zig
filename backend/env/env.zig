//! We use loadKvpComptime to embed environment variables at compile time
pub const env = @import("loadKvp.zig").loadKvpComptime(@embedFile("../.env"));
pub const auth = env.get("AUTH").?;

