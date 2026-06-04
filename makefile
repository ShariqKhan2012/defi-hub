build:
	cd contracts && forge build

clean:
	cd contracts && forge clean

test:
	cd contracts && forge test

install:
	cd frontend && npm install

dev:
	cd frontend && npm run dev