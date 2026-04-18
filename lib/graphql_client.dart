import 'package:graphql/client.dart';

/// Shared GraphQL client instance for the app.
final graphqlClient = GraphQLClient(
  link: HttpLink('http://localhost:8080/graphql'),
  cache: GraphQLCache(),
);
