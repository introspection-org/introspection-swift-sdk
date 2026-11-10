import Foundation

#if Walk
import IntrospectionWalk

exit(await WalkCommand.run())
#else
print("introspection-walk was built without its trait: swift run --traits Walk introspection-walk")
exit(1)
#endif
