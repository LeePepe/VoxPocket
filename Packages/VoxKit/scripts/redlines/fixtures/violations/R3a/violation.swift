// expected-diagnostic: cannot convert value of type 'String' to expected argument type 'StaticString'
import VoxCore
let runtimeString = "runtime"
let logger = NoopVoxLogger()
logger.info(runtimeString)
