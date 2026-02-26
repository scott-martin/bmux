package auth

import (
	"net/http"
	"testing"

	"github.com/go-rod/rod/lib/proto"
)

func TestIsCookieRelevant(t *testing.T) {
	b := &BrowserAuth{}

	tests := []struct {
		name       string
		cookie     *proto.NetworkCookie
		targetHost string
		want       bool
	}{
		{
			name: "exact match",
			cookie: &proto.NetworkCookie{
				Domain: "example.com",
			},
			targetHost: "example.com",
			want:       true,
		},
		{
			name: "exact match with leading dot",
			cookie: &proto.NetworkCookie{
				Domain: ".example.com",
			},
			targetHost: "example.com",
			want:       true,
		},
		{
			name: "subdomain match",
			cookie: &proto.NetworkCookie{
				Domain: ".omaticcloud.io",
			},
			targetHost: "aks-dev.omaticcloud.io",
			want:       true,
		},
		{
			name: "subdomain cookie for parent",
			cookie: &proto.NetworkCookie{
				Domain: "omaticcloud.io",
			},
			targetHost: "aks-dev.omaticcloud.io",
			want:       true,
		},
		{
			name: "no match - different domain",
			cookie: &proto.NetworkCookie{
				Domain: "other.com",
			},
			targetHost: "example.com",
			want:       false,
		},
		{
			name: "no match - partial string match but not domain",
			cookie: &proto.NetworkCookie{
				Domain: "example.com",
			},
			targetHost: "notexample.com",
			want:       false,
		},
		{
			name: "empty domain - always relevant",
			cookie: &proto.NetworkCookie{
				Domain: "",
			},
			targetHost: "any.host.com",
			want:       true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := b.isCookieRelevant(tt.cookie, tt.targetHost)
			if got != tt.want {
				t.Errorf("isCookieRelevant() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestConvertSameSite(t *testing.T) {
	b := &BrowserAuth{}

	tests := []struct {
		name     string
		sameSite proto.NetworkCookieSameSite
		want     http.SameSite
	}{
		{
			name:     "Strict",
			sameSite: proto.NetworkCookieSameSiteStrict,
			want:     http.SameSiteStrictMode,
		},
		{
			name:     "Lax",
			sameSite: proto.NetworkCookieSameSiteLax,
			want:     http.SameSiteLaxMode,
		},
		{
			name:     "None",
			sameSite: proto.NetworkCookieSameSiteNone,
			want:     http.SameSiteNoneMode,
		},
		{
			name:     "Unspecified",
			sameSite: proto.NetworkCookieSameSite(""),
			want:     http.SameSiteDefaultMode,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := b.convertSameSite(tt.sameSite)
			if got != tt.want {
				t.Errorf("convertSameSite() = %v, want %v", got, tt.want)
			}
		})
	}
}
