/// User-driven sort direction for a column header.
enum SortDirection {
  asc,
  desc;

  /// Wire value matching the backend `SortDirection` GraphQL enum.
  String get wireValue => this == SortDirection.asc ? 'ASC' : 'DESC';
}

/// Cycles a column's sort state on each header click:
///   null -> ASC -> DESC -> null
///
/// Returns the next direction, or null when the column should clear.
SortDirection? cycleSortDirection(
  SortDirection? current, {
  required bool isActive,
}) {
  if (!isActive) return SortDirection.asc;
  return switch (current) {
    SortDirection.asc => SortDirection.desc,
    SortDirection.desc => null,
    null => SortDirection.asc,
  };
}
