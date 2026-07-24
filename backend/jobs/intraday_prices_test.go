package jobs

import (
	"testing"
	"time"
)

func TestNextIntradaySlot(t *testing.T) {
	ist := time.FixedZone("IST", 5*60*60+30*60)

	cases := []struct {
		name string
		now  time.Time
		want time.Time
	}{
		{
			name: "exact open",
			now:  time.Date(2026, 7, 24, 9, 0, 0, 0, ist), // Friday
			want: time.Date(2026, 7, 24, 9, 0, 0, 0, ist),
		},
		{
			name: "mid slot rounds up",
			now:  time.Date(2026, 7, 24, 9, 7, 30, 0, ist),
			want: time.Date(2026, 7, 24, 9, 15, 0, 0, ist),
		},
		{
			name: "last slot inclusive",
			now:  time.Date(2026, 7, 24, 15, 30, 0, 0, ist),
			want: time.Date(2026, 7, 24, 15, 30, 0, 0, ist),
		},
		{
			name: "after close to monday",
			now:  time.Date(2026, 7, 24, 15, 31, 0, 0, ist), // Friday after close
			want: time.Date(2026, 7, 27, 9, 0, 0, 0, ist),   // Monday
		},
		{
			name: "before open same day",
			now:  time.Date(2026, 7, 24, 8, 0, 0, 0, ist),
			want: time.Date(2026, 7, 24, 9, 0, 0, 0, ist),
		},
		{
			name: "saturday to monday",
			now:  time.Date(2026, 7, 25, 12, 0, 0, 0, ist),
			want: time.Date(2026, 7, 27, 9, 0, 0, 0, ist),
		},
		{
			name: "past exact minute advances",
			now:  time.Date(2026, 7, 24, 9, 0, 1, 0, ist),
			want: time.Date(2026, 7, 24, 9, 15, 0, 0, ist),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := nextIntradaySlot(tc.now)
			if !got.Equal(tc.want) {
				t.Fatalf("got %s want %s", got.Format(time.RFC3339), tc.want.Format(time.RFC3339))
			}
		})
	}
}
