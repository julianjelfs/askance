import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// The single non-consumable that unlocks keeping and exporting studies.
///
/// Leave empty to run against [SimulatedPurchaseService]. Fill it in once the
/// product exists in App Store Connect and the Play Console, and the store
/// implementation below takes over with no other change.
const String kProductId = '';

const String kPriceLabel = '£3.99';

enum PurchaseOutcome { success, cancelled, failed }

abstract class PurchaseService {
  Future<bool> isAvailable();

  /// Price as the store reports it, falling back to the designed label.
  Future<String> priceLabel();

  Future<PurchaseOutcome> purchase();

  /// Required by App Store review, and the only way back after a reinstall.
  Future<PurchaseOutcome> restore();
}

/// Stands in until the store products exist. Confirms after the ~900ms the
/// design specifies, so the "Confirming…" state is exercised for real.
class SimulatedPurchaseService implements PurchaseService {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String> priceLabel() async => kPriceLabel;

  @override
  Future<PurchaseOutcome> purchase() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return PurchaseOutcome.success;
  }

  @override
  Future<PurchaseOutcome> restore() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return PurchaseOutcome.success;
  }
}

/// The real thing: a single non-consumable, bought once, restorable.
class StorePurchaseService implements PurchaseService {
  StorePurchaseService();

  final InAppPurchase _iap = InAppPurchase.instance;
  ProductDetails? _product;

  @override
  Future<bool> isAvailable() async {
    if (kProductId.isEmpty) return false;
    if (!await _iap.isAvailable()) return false;
    final response = await _iap.queryProductDetails({kProductId});
    _product = response.productDetails.firstOrNull;
    return _product != null;
  }

  @override
  Future<String> priceLabel() async => _product?.price ?? kPriceLabel;

  @override
  Future<PurchaseOutcome> purchase() async {
    final product = _product;
    if (product == null) return PurchaseOutcome.failed;
    final completer = Completer<PurchaseOutcome>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.productID != kProductId) continue;
        switch (purchase.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            if (!completer.isCompleted) {
              completer.complete(PurchaseOutcome.success);
            }
          case PurchaseStatus.canceled:
            if (!completer.isCompleted) {
              completer.complete(PurchaseOutcome.cancelled);
            }
          case PurchaseStatus.error:
            debugPrint('purchase error: ${purchase.error}');
            if (!completer.isCompleted) {
              completer.complete(PurchaseOutcome.failed);
            }
          case PurchaseStatus.pending:
            break;
        }
      }
    });
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      return await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => PurchaseOutcome.failed,
      );
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<PurchaseOutcome> restore() async {
    final completer = Completer<PurchaseOutcome>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.productID != kProductId) continue;
        if (purchase.status == PurchaseStatus.restored ||
            purchase.status == PurchaseStatus.purchased) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          if (!completer.isCompleted) {
            completer.complete(PurchaseOutcome.success);
          }
        }
      }
    });
    try {
      await _iap.restorePurchases();
      // No restored purchase inside the window means there was nothing to
      // restore, which is a normal answer rather than an error.
      return await completer.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => PurchaseOutcome.failed,
      );
    } finally {
      await sub.cancel();
    }
  }
}
