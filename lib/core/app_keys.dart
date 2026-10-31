import 'package:flutter/material.dart';

/// Lets app-wide widgets (such as the party badge) open sheets and show
/// notices without a BuildContext from a particular page.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
