package jobs

import (
	"testing"
	"time"
)

func TestNextWeekdayElevenPM(t *testing.T) {
	ist := time.FixedZone("IST", 5*60*60+30*60)

	cases := []struct {
		name string
		now  time.Time
		want time.Time
	}{
		{
			name: "weekday before 23 same day",
			now:  time.Date(2026, 8, 21, 14, 0, 0, 0, ist), // Friday
			want: time.Date(2026, 8, 21, 23, 0, 0, 0, ist),
		},
		{
			name: "exact 23 weekday",
			now:  time.Date(2026, 8, 21, 23, 0, 0, 0, ist),
			want: time.Date(2026, 8, 21, 23, 0, 0, 0, ist),
		},
		{
			name: "friday after 23 next monday",
			now:  time.Date(2026, 8, 21, 23, 0, 1, 0, ist),
			want: time.Date(2026, 8, 24, 23, 0, 0, 0, ist),
		},
		{
			name: "saturday to monday",
			now:  time.Date(2026, 8, 22, 10, 0, 0, 0, ist),
			want: time.Date(2026, 8, 24, 23, 0, 0, 0, ist),
		},
		{
			name: "sunday to monday",
			now:  time.Date(2026, 8, 23, 23, 30, 0, 0, ist),
			want: time.Date(2026, 8, 24, 23, 0, 0, 0, ist),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := nextWeekdayElevenPM(tc.now)
			if !got.Equal(tc.want) {
				t.Fatalf("got %s want %s", got.Format(time.RFC3339), tc.want.Format(time.RFC3339))
			}
		})
	}
}
