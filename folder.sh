#!/bin/bash

# Create all directories (properly escaped)
mkdir -p \
  fraction-estate \
  "fraction-estate/apps/web/app/(public)/marketplace" \
  "fraction-estate/apps/web/app/(public)/dashboard" \
  fraction-estate/apps/web/components \
  fraction-estate/apps/web/lib \
  fraction-estate/packages/core/dapp/validators \
  fraction-estate/packages/core/scripts \
  fraction-estate/packages/db/prisma \
  fraction-estate/packages/ui/components/auth \
  fraction-estate/packages/ui/components/marketplace \
  fraction-estate/.github/workflows

echo "✅ All folders created successfully"
