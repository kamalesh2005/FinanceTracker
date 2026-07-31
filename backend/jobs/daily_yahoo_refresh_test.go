package jobs

import (
	"testing"
	"time"
)

func TestNextDailySixAM(t *testing.T) {
	ist := time.FixedZone("IST", 5*60*60+30*60)

	cases := []struct {
		name string
		now  time.Time
		want time.Time
	}{
		{
			name: "exact six",
			now:  time.Date(2026, 7, 31, 6, 0, 0, 0, ist),
			want: time.Date(2026, 7, 31, 6, 0, 0, 0, ist),
		},
		{
			name: "before six same day",
			now:  time.Date(2026, 7, 31, 5, 59, 59, 0, ist),
			want: time.Date(2026, 7, 31, 6, 0, 0, 0, ist),
		},
		{
			name: "after six next day",
			now:  time.Date(2026, 7, 31, 6, 0, 1, 0, ist),
			want: time.Date(2026, 8, 1, 6, 0, 0, 0, ist),
		},
		{
			name: "afternoon next day",
			now:  time.Date(2026, 7, 31, 14, 0, 0, 0, ist),
			want: time.Date(2026, 8, 1, 6, 0, 0, 0, ist),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := nextDailySixAM(tc.now)
			if !got.Equal(tc.want) {
				t.Fatalf("got %s want %s", got.Format(time.RFC3339), tc.want.Format(time.RFC3339))
			}
		})
	}
}
