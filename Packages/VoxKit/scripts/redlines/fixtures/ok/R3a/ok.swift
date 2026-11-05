import VoxCore
let logger = NoopVoxLogger()
logger.info("static_msg", fields: [.int("count", 1)])
