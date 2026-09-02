package jobs

import (
	"testing"
	"time"
)

func TestNextDailyTenPM(t *testing.T) {
	ist := time.FixedZone("IST", 5*60*60+30*60)

	cases := []struct {
		name string
		now  time.Time
		want time.Time
	}{
		{
			name: "exact ten",
			now:  time.Date(2026, 7, 31, 22, 0, 0, 0, ist),
			want: time.Date(2026, 7, 31, 22, 0, 0, 0, ist),
		},
		{
			name: "before ten same day",
			now:  time.Date(2026, 7, 31, 21, 59, 59, 0, ist),
			want: time.Date(2026, 7, 31, 22, 0, 0, 0, ist),
		},
		{
			name: "after ten next day",
			now:  time.Date(2026, 7, 31, 22, 0, 1, 0, ist),
			want: time.Date(2026, 8, 1, 22, 0, 0, 0, ist),
		},
		{
			name: "afternoon same day",
			now:  time.Date(2026, 7, 31, 14, 0, 0, 0, ist),
			want: time.Date(2026, 7, 31, 22, 0, 0, 0, ist),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := nextDailyTenPM(tc.now)
			if !got.Equal(tc.want) {
				t.Fatalf("got %s want %s", got.Format(time.RFC3339), tc.want.Format(time.RFC3339))
			}
		})
	}
}
