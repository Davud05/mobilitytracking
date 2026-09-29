using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EfStep8.Migrations
{
    /// <inheritdoc />
    public partial class TicketProductId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "tickets_product_fk",
                table: "tickets");

            migrationBuilder.DropIndex(
                name: "IX_tickets_product_code",
                table: "tickets");

            migrationBuilder.DropColumn(
                name: "product_code",
                table: "tickets");

            migrationBuilder.AddColumn<Guid>(
                name: "product_id",
                table: "tickets",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.AddColumn<Guid>(
                name: "id",
                table: "products",
                type: "uuid",
                nullable: false,
                defaultValueSql: "gen_random_uuid()");

            migrationBuilder.AddUniqueConstraint(
                name: "products_id_unique",
                table: "products",
                column: "id");

            migrationBuilder.CreateIndex(
                name: "IX_tickets_product_id",
                table: "tickets",
                column: "product_id");

            migrationBuilder.AddForeignKey(
                name: "tickets_product_id_fk",
                table: "tickets",
                column: "product_id",
                principalTable: "products",
                principalColumn: "id",
                onDelete: ReferentialAction.Cascade);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "tickets_product_id_fk",
                table: "tickets");

            migrationBuilder.DropIndex(
                name: "IX_tickets_product_id",
                table: "tickets");

            migrationBuilder.DropUniqueConstraint(
                name: "products_id_unique",
                table: "products");

            migrationBuilder.DropColumn(
                name: "product_id",
                table: "tickets");

            migrationBuilder.DropColumn(
                name: "id",
                table: "products");

            migrationBuilder.AddColumn<string>(
                name: "product_code",
                table: "tickets",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateIndex(
                name: "IX_tickets_product_code",
                table: "tickets",
                column: "product_code");

            migrationBuilder.AddForeignKey(
                name: "tickets_product_fk",
                table: "tickets",
                column: "product_code",
                principalTable: "products",
                principalColumn: "code",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
