from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg2://zameel:zameel@localhost:5434/zameel"
    jwt_secret: str = "change-me-in-.env"
    jwt_expire_days: int = 90
    data_dir: str = "/data"

    class Config:
        env_file = ".env"


settings = Settings()
