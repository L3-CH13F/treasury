package db

import "github.com/google/uuid"

type database string

const (
	postgresql database = "pg"
	sqlite     database = "sqlite"
)

func InitializeDB(db database, url string) error {
	return nil
}

func InitializeSqlite(url string) error {
	return nil
}

type TreasuryUser struct {
	id           uuid.UUID
	name         string
	email        string
	organization TreasuryOrganization
	idp          TreasuryIdP
}

type TreasuryOrganization struct{}
type TreasuryIdP struct{}
type TreasuryGroup struct{}

type TreasuryDB interface {
	UserVault(*TreasuryUser)
	GroupVault(*TreasuryGroup)
	AuthenticateUser()
	AuthorizeUser()
}
