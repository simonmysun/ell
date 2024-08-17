#!/usr/bin/env bash

ell --api-style ell_echo -m gpt-4o --api-stream false test;

ell --api-style ell_echo -t default-gemini test;
