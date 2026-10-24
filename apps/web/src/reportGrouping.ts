export interface ReportLocation {
  id: string;
  latitude: number;
  longitude: number;
  submittedAt: string;
}

export interface ReportGroup<T extends ReportLocation> {
  anchor: T;
  members: T[];
}

export function groupReportsByFirstAnchor<T extends ReportLocation>(
  reports: readonly T[],
): ReportGroup<T>[] {
  const groups: ReportGroup<T>[] = [];
  const ordered = [...reports].sort(
    (left, right) =>
      Date.parse(left.submittedAt) - Date.parse(right.submittedAt) ||
      left.id.localeCompare(right.id),
  );
  for (const report of ordered) {
    if (
      !Number.isFinite(report.latitude) ||
      !Number.isFinite(report.longitude) ||
      report.latitude < -90 ||
      report.latitude > 90 ||
      report.longitude < -180 ||
      report.longitude > 180
    ) {
      throw new Error(`Citizen report ${report.id} has invalid coordinates.`);
    }
    const group = groups.find(
      ({ anchor }) =>
        distanceInMeters(
          anchor.latitude,
          anchor.longitude,
          report.latitude,
          report.longitude,
        ) <= 1000,
    );
    if (group) group.members.push(report);
    else groups.push({ anchor: report, members: [report] });
  }
  return groups;
}

export function priorityWithReportVolume(priorities: readonly number[]): number {
  if (priorities.length === 0) {
    throw new Error("A report group must contain at least one priority score.");
  }
  if (priorities.some((priority) => !Number.isFinite(priority))) {
    throw new Error("Report priority scores must be finite numbers.");
  }
  return Math.min(
    100,
    Math.max(...priorities) + 5 * (priorities.length - 1),
  );
}

function distanceInMeters(
  latitudeA: number,
  longitudeA: number,
  latitudeB: number,
  longitudeB: number,
): number {
  const radians = (degrees: number) => (degrees * Math.PI) / 180;
  const latitudeDelta = radians(latitudeB - latitudeA);
  const longitudeDelta = radians(longitudeB - longitudeA);
  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(radians(latitudeA)) *
      Math.cos(radians(latitudeB)) *
      Math.sin(longitudeDelta / 2) ** 2;
  return (
    6_371_000 *
    2 *
    Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
  );
}
