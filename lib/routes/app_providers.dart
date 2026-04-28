import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';

List<BlocProvider<StateStreamableSource<Object?>>> getAppProviders() {
  return <BlocProvider<StateStreamableSource<Object?>>>[
    BlocProvider<GameBloc>(
      create: (final _) => GameBloc()..add(const InitialEvent()),
    ),
  ];
}
