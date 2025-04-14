import 'package:flutter/material.dart';

// GoRouter configuration
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _InitialScreen(),
    ),
  ],
  initialLocation: '/',
  observers: [PosthogObserver()],
);


class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
        routerConfig: _router,
        title: 'Flutter App',
      )
  }
}