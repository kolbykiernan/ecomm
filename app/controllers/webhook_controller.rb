class WebhookController < ApplicationController
    skip_forgery_protection

    def stripe
        stripe_secret_key = ENV['STRIPE_SECRET_KEY']
        Stripe.api_key = stripe_secret_key
        payload = request.body.read
        sig_header = request.env['HTTP_STRIPE_SIGNATURE']
        endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']
        event = nil

        begin
            event= Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
        rescue JSON::ParserErro => e
            status 400
            return
        rescue Stripe::SignatureVerificationError => e
            puts "Webhook signature verification failed."
            status 400
            return
        end

        case event.type
        when 'checkout.session.completed'
            session = event.data.object
            shipping_details = session['shipping_details']
            address = "#{shipping_details['address']['line1'] shipping_details['address']['city']}, #{shipping_details['address']['state']} #{shipping_details['address']['postal_code']}"
            order = Order.create!(customer_email: session["customer_details"]["email"], total: session["amount_total"], address: address, fulfilled: false)
            full_session = Stripe::Checkout.retrieve({
                id: session.id,
                expand: ['line_items']
            })
            line_items = full_session.line_items
            line_items["data"].each do |item|
                product = Stripe::Product.retrieve(item["price"]["product"])
                product_id =product["metadata"]["product_id"].to_i
                OrderProduct.create!(order: order, product_id: product_id, quantity: item["quantity"], size: product ["metadata"]["size"])
                ProductStock.find(product["metadata"]["product_stock_id"]).decrement!(amount, item["quantity"])
            end
        else
            puts "Unhandled event type: #{event.type}"
            
        end

        render json: { message: "success" }
    end
end